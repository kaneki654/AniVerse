import base64
import re
import httpx
import urllib.parse
from typing import Dict, Any, List, Optional
from selectolax.parser import HTMLParser

from .base import BaseProvider
from ..extractors import megaplay
from ..services import anilist_media
from ..services import episode_map

class AniWatchProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "AniWatch"

    @property
    def base_url(self) -> str:
        return "https://aniwatch.co.at"

    @property
    def rest_url(self) -> str:
        return f"{self.base_url}/wp-json/hianime/v1"

    def _headers(self, referer: str = None) -> Dict[str, str]:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/html, */*",
        }
        if referer:
            headers["Referer"] = referer
        return headers

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            try:
                anime_id = await self.map_anime(client, anilist_id, category)
                if not anime_id:
                    return {"error": "Anime not found on AniWatch (Mapping failed)"}

                episode_id = await self.get_episode(client, anime_id, episode, anilist_id)
                if not episode_id:
                    return {"error": f"Episode {episode} not found on AniWatch"}

                servers = await self.get_servers(client, episode_id, category)
                if not servers:
                    return {"error": "No embed servers found on AniWatch (Might be Cloudflare blocked)"}

                expected_duration = self._expected_duration(
                    await self._anilist_info(client, anilist_id))
                return await self.extract(client, servers, expected_duration=expected_duration)
            except Exception as e:
                return {"error": f"AniWatch extraction failed: {str(e)}"}

    async def _anilist_info(self, client: httpx.AsyncClient, anilist_id: str) -> Dict[str, Any]:
        """Fetch AniList title + episodes + duration + format for mapping and verification."""
        return await anilist_media.get_media(client, anilist_id)

    @staticmethod
    def _expected_duration(info: Optional[Dict[str, Any]]) -> Optional[int]:
        """Expected episode duration in seconds (AniList duration x 60, default 24min).

        Takes the info explicitly: this provider is a module-level singleton shared
        by every concurrent resolve, so parking it on `self` let another anime's
        request overwrite it between mapping and verification.
        """
        if not info:
            return None
        return int(info.get("duration") or 24) * 60

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str = "sub") -> str:
        """Map AniList ID to the AniWatch anime post ID via search suggestions.

        Ranks candidates by exact normalized-title match first (then fuzzy),
        skips movie/special/ONA/OVA candidates when AniList format is TV, and
        rejects records whose episode count contradicts AniList (broken data).
        """
        try:
            info = await self._anilist_info(client, anilist_id)
            title_ro = info["title_ro"]
            title_en = info["title_en"]
            anilist_format = info.get("format") or "TV"
            anilist_episodes = info.get("episodes")

            # Reference titles used for ranking (year parentheticals stripped so
            # "Hunter x Hunter (2011)" still matches AniWatch's "Hunter x Hunter").
            norm_titles = []
            for t in (title_ro, title_en):
                nt = self.normalize_title(self.clean_title(t))
                if nt and nt not in norm_titles:
                    norm_titles.append(nt)

            candidates = []
            seen_slugs = set()

            for t in self._search_variants(title_ro, title_en):
                search_url = f"{self.rest_url}/search/suggestions?keyword={urllib.parse.quote(t)}"
                try:
                    search_resp = await client.get(search_url, headers=self._headers())
                except Exception:
                    continue
                if search_resp.status_code != 200:
                    continue

                try:
                    search_data = search_resp.json()
                except Exception:
                    continue
                if not search_data.get("success") or not search_data.get("html"):
                    continue

                tree = HTMLParser(search_data["html"])
                for link in tree.css('a[href*="/anime/"]'):
                    anime_url = link.attributes.get("href", "")
                    m = re.search(r'/anime/([^/]+)/?$', anime_url)
                    if not m:
                        continue
                    slug = m.group(1)
                    if slug in seen_slugs:
                        continue
                    seen_slugs.add(slug)
                    display = link.attributes.get("data-jname") or ""
                    if not display:
                        film = link.css_first(".film-name")
                        if film:
                            display = film.text(strip=True) or ""
                    if not display:
                        display = link.text(strip=True) or ""
                    candidates.append({
                        "slug": slug,
                        "display": display.strip(),
                        "search_title": t,
                        "href": anime_url,
                    })

                # An exact title hit means the later, looser variants can only add
                # noise -- but only when it is the part AniList asked for.
                # normalize_title() drops "Part N", so when AniList names no part
                # a hit on "... Part 2" looks exact while Part 1 is still missing
                # from the results; stopping there is what pinned "The Final
                # Season" to Part 2. Keep searching until the parts are all in.
                want_part_now = max(self.part_of(title_ro), self.part_of(title_en))
                if any(self.normalize_title(c["display"]) in norm_titles
                       and self.part_of(c["display"]) == want_part_now
                       for c in candidates):
                    break

            if not candidates:
                return ""

            want_season = max(self.season_of(title_ro), self.season_of(title_en))
            want_part = max(self.part_of(title_ro), self.part_of(title_en))

            # Identity is decided by the title (same rule as the other providers),
            # not by episode count: an airing show legitimately has fewer episodes
            # on-site than AniList's planned total.
            def alias_part(cand) -> int:
                return max(self.part_of(cand["display"]),
                           self.part_of(cand["slug"].replace("-", " ")))

            def agrees(cand) -> bool:
                for alias in (cand["display"], cand["slug"].replace("-", " ")):
                    if not alias or self.season_of(alias) != want_season:
                        continue
                    # A titled part only matches the part AniList asked for.
                    # When AniList names no part the entry is the first one, but
                    # every part still stays in the running so the episode-count
                    # tie-break below can confirm which it really is.
                    if want_part and self.part_of(alias) != want_part:
                        continue
                    na = self.normalize_title(self.clean_title(alias))
                    if any(self.titles_agree(na, nt) for nt in norm_titles):
                        return True
                return False

            matches = [c for c in candidates if agrees(c)]
            if not matches:
                print(f"AniWatch map: no candidate matched {norm_titles[0]!r} "
                      f"(season {want_season}, part {want_part}); "
                      f"{[c['slug'] for c in candidates][:4]} -> rejected")
                return ""

            # Several parts of one season survive when AniList names no part
            # ("The Final Season" vs the site's Part 1/2/3). Site search order is
            # meaningless there, so try the episode-count match first and fall
            # back to the lowest part number.
            if len(matches) > 1:
                counts = {}
                for cand in matches:
                    counts[cand["slug"]] = await self._candidate_episode_count(client, cand)

                # Episode titles settle it outright when Ani.zip knows them:
                # counts can legitimately differ, titles cannot.
                expected = await episode_map.episode_titles(client, anilist_id)
                scores = {
                    c["slug"]: episode_map.match_score(expected, c.get("_ep_titles") or {})
                    for c in matches
                }

                def rank(cand):
                    score = scores.get(cand["slug"])
                    total = counts.get(cand["slug"])
                    exact = anilist_episodes and total == anilist_episodes
                    # Unknown score (None) must not outrank a confirmed match,
                    # nor be treated as a mismatch - it just falls through to
                    # the count and part heuristics.
                    return (
                        0 if (score is not None and score >= 0.5) else 1,
                        0 if exact else 1,
                        alias_part(cand) or 99,
                    )

                matches.sort(key=rank)
                print(f"AniWatch map: {len(matches)} candidates for {norm_titles[0]!r} "
                      f"(want {anilist_episodes} eps) -> "
                      f"{[(c['slug'], counts.get(c['slug']), scores.get(c['slug'])) for c in matches[:3]]}")

            for cand in matches:
                if anilist_format == "TV":
                    nd = self.normalize_title(cand["display"])
                    if re.search(r'\b(?:movie|special|ona|ova|spinoff|spin[- ]?off)\b', nd):
                        continue

                if cand.get("_anime_id"):
                    anime_id = cand["_anime_id"]
                    total = cand["_total"]
                else:
                    detail_resp = await client.get(f"{self.base_url}/anime/{cand['slug']}/", headers=self._headers())
                    if detail_resp.status_code != 200:
                        continue

                    id_match = re.search(r'data-animeid="(\d+)"', detail_resp.text)
                    if not id_match:
                        continue
                    anime_id = id_match.group(1)

                    total = await self._episode_count(client, anime_id)

                if total is None:
                    continue
                if total == 0 and anilist_episodes:
                    print(f"AniWatch map: {cand['display']} has broken episode list -> rejected")
                    continue
                # No episode-count identity check: the title already decided identity,
                # and counts legitimately differ both ways - an airing show has fewer
                # than AniList's planned total, a split-cour record merges both parts.

                return anime_id

        except Exception as e:
            print(f"AniWatch Map error: {type(e).__name__}: {e}")
        return ""

    def _search_variants(self, title_ro: str, title_en: str) -> List[str]:
        """Ordered, deduped search keywords, most specific first.

        Falls back to progressively shorter forms so a title AniWatch indexes
        without its season/part qualifier is still reachable.
        """
        cleaned = [self.clean_title(t) for t in (title_ro, title_en)]

        def flatten(v: str) -> str:
            # "Naruto: Shippuden" -> "Naruto Shippuden" (AniWatch drops the colon).
            return re.sub(r'\s+', ' ', re.sub(r'[:/–—-]', ' ', v)).strip()

        def strip_season(v: str) -> str:
            v = re.sub(r'\s+(?:season|part|cour|s)\s*\d+\s*$', '', v, flags=re.I)
            return re.sub(r'\s+\d+(?:st|nd|rd|th)\s+season\s*$', '', v, flags=re.I)

        # Tiers, most faithful first: a looser tier is only reached when the
        # tighter ones return nothing, so the lossy prefix-split stays last.
        tiers = [
            cleaned,
            [flatten(c) for c in cleaned],
            [strip_season(c) for c in cleaned],
            [strip_season(flatten(c)) for c in cleaned],
            [re.split(r'\s*[:–—-]\s+', c)[0] for c in cleaned],
        ]

        variants: List[str] = []
        seen = set()
        for tier in tiers:
            for v in tier:
                v = (v or "").strip(" -:")
                if v and v.lower() not in seen:
                    seen.add(v.lower())
                    variants.append(v)
        return variants

    def _fuzz_score(self, a: str, b: str) -> int:
        try:
            from rapidfuzz import fuzz
            return int(fuzz.ratio(a, b))
        except Exception:
            return 0

    async def _candidate_episode_count(self, client: httpx.AsyncClient, cand: Dict[str, Any]) -> Optional[int]:
        """Episode count for a search candidate, resolving its anime id first.

        Both are cached on the candidate so the selection loop that follows does
        not fetch the same two pages again.
        """
        if "_total" in cand:
            return cand["_total"]
        cand["_anime_id"] = None
        cand["_total"] = None
        try:
            resp = await client.get(f"{self.base_url}/anime/{cand['slug']}/", headers=self._headers())
            if resp.status_code != 200:
                return None
            m = re.search(r'data-animeid="(\d+)"', resp.text)
            if not m:
                return None
            cand["_anime_id"] = m.group(1)
            cand["_total"], items = await self._episode_list(client, cand["_anime_id"])
            cand["_ep_titles"] = {n: v["title"] for n, v in items.items() if v["title"]}
        except Exception as e:
            print(f"AniWatch candidate count error ({cand.get('slug')}): {e}")
        return cand["_total"]

    async def _episode_list(self, client: httpx.AsyncClient, anime_id: str):
        """(total episodes, {episode number: {"id", "title"}}) in one request.

        The titles come free with the count and are what lets map_anime confirm
        a candidate is the right part rather than inferring it from the name.
        """
        try:
            url = f"{self.rest_url}/episode/list/{anime_id}"
            resp = await client.get(url, headers=self._headers())
            if resp.status_code != 200:
                return None, {}
            data = resp.json()
            if not data.get("status"):
                return None, {}
            total = data.get("totalItems")
            items = {}
            for item in HTMLParser(data.get("html", "")).css(".ep-item"):
                num = item.attributes.get("data-number")
                if not num:
                    continue
                items[str(num)] = {
                    "id": item.attributes.get("data-id", ""),
                    "title": item.attributes.get("title") or "",
                }
            return (total if isinstance(total, int) else None), items
        except Exception:
            return None, {}

    async def _episode_count(self, client: httpx.AsyncClient, anime_id: str) -> Optional[int]:
        """Episode count via totalItems; 0 or missing means a broken record."""
        try:
            url = f"{self.rest_url}/episode/list/{anime_id}"
            resp = await client.get(url, headers=self._headers())
            if resp.status_code != 200:
                return None
            data = resp.json()
            if not data.get("status"):
                return None
            total = data.get("totalItems")
            if not isinstance(total, int):
                return None
            return total
        except Exception:
            return None

    async def get_episode(self, client: httpx.AsyncClient, anime_id: str, episode_num: int,
                          anilist_id: str = None) -> str:
        """AniWatch post ID for an episode, confirmed against Ani.zip's title.

        Matching on the site's own numbering alone is wrong whenever the record
        merges two cours that AniList lists separately: AniList episode 1 of the
        second cour is episode 13 on the merged page. When the titles disagree,
        find the episode that actually carries the expected title instead.
        """
        try:
            _total, items = await self._episode_list(client, anime_id)
            if not items:
                return ""

            wanted = str(episode_num)
            expected = {}
            if anilist_id:
                expected = await episode_map.episode_titles(client, anilist_id)
            expected_title = expected.get(wanted)

            entry = items.get(wanted)
            if entry and (not expected_title
                          or episode_map.titles_match(expected_title, entry["title"])):
                return entry["id"]

            if expected_title:
                for num, item in items.items():
                    if episode_map.titles_match(expected_title, item["title"]):
                        if num != wanted:
                            print(f"AniWatch episode: {anilist_id} ep {wanted} is "
                                  f"ep {num} on this record ({item['title']!r})")
                        return item["id"]
                # Sources word the same episode differently ("To You, 2000 Years
                # in the Future" vs "To You, in 2000 Years"), so a miss here is
                # not evidence of the wrong episode. Correct only on a positive
                # match; otherwise keep the site's own numbering.
                print(f"AniWatch episode: no title match for ep {wanted} on record "
                      f"{anime_id}; keeping site numbering")

            return entry["id"] if entry else ""
        except Exception as e:
            print(f"AniWatch Episode error: {e}")
        return ""

    async def get_servers(self, client: httpx.AsyncClient, episode_id: str, category: str = "sub") -> List[Dict[str, str]]:
        """Fetch embed servers; server links are base64 encoded inside data-hash"""
        servers = []
        try:
            url = f"{self.rest_url}/episode/servers/{episode_id}"
            resp = await client.get(url, headers=self._headers())
            if resp.status_code != 200:
                return servers

            data = resp.json()
            if not data.get("status"):
                return servers

            tree = HTMLParser(data.get("html", ""))
            for item in tree.css(".server-item"):
                servers.append({
                    "name": item.attributes.get("data-server-name", "AniWatch"),
                    "type": item.attributes.get("data-type", "sub"),
                    "hash": item.attributes.get("data-hash", "")
                })

            if category == "sub":
                servers = [s for s in servers if s.get("type") == "sub"]
            elif category == "dub":
                dub_servers = [s for s in servers if s.get("type") == "dub"]
                if dub_servers:
                    servers = dub_servers
                else:
                    # Never silently degrade a dub request to sub streams.
                    return []

            for s in servers:
                try:
                    s["url"] = base64.b64decode(s.pop("hash")).decode("utf-8", "ignore")
                except Exception:
                    s["url"] = ""

            return [s for s in servers if s.get("url")]
        except Exception as e:
            print(f"AniWatch Servers error: {e}")
            return servers

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]], expected_duration: Optional[int] = None) -> Dict[str, Any]:
        """
        Fetch each embed page and pull the direct video source (mp4 or m3u8)
        out of the <video>/<source> tags, or for megaplay embeds resolve the
        playable master.m3u8 via the getSources endpoint.
        """
        streams = []
        subtitles = []
        seen = set()
        intro = outro = None

        for server in servers:
            try:
                embed_url = server["url"]
                server_name = server.get("name", "AniWatch")
                category = server.get("type", "sub")

                mega = self._match_megaplay(embed_url)
                if mega:
                    result = await self._extract_megaplay(client, embed_url, mega, server_name,
                                                          expected_duration=expected_duration)
                    # Skip markers come from the megaplay payload; keep the first
                    # server that actually has them.
                    intro = intro or result.get("intro")
                    outro = outro or result.get("outro")
                    for stream in result.get("streams", []):
                        if stream["url"] not in seen:
                            seen.add(stream["url"])
                            streams.append(stream)
                    for sub in result.get("subtitles", []):
                        for existing in subtitles:
                            if existing.get("url") == sub.get("url"):
                                break
                        else:
                            subtitles.append(sub)
                    continue

                resp = await client.get(embed_url, headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "Referer": f"{self.base_url}/",
                    "Origin": self.base_url,
                })
                if resp.status_code != 200:
                    continue

                if m3u8_url := self._find_m3u8(resp.text):
                    final_url = m3u8_url
                else:
                    final_url = self._find_source(resp.text)
                    if not final_url:
                        continue

                # Resolve the 302 so the player/proxy gets a direct playable file
                try:
                    head = await client.head(final_url, headers={
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                        "Referer": embed_url,
                    })
                    if head.status_code == 200 and head.url:
                        final_url = str(head.url)
                except Exception:
                    pass

                if final_url in seen:
                    continue
                seen.add(final_url)

                streams.append({
                    "quality": "auto",
                    "url": final_url,
                    "server": server_name,
                    "category": category,
                })
            except Exception as e:
                print(f"AniWatch Extract Failed ({server.get('name')}): {e}")
                continue

        return {"streams": streams, "subtitles": subtitles,
                "intro": intro, "outro": outro}

    def _match_megaplay(self, embed_url: str):
        return megaplay.match_megaplay(embed_url)

    async def _extract_megaplay(self, client: httpx.AsyncClient, embed_url: str, mega: Dict[str, str], server_name: str,
                                expected_duration: Optional[int] = None) -> Dict[str, Any]:
        """Resolve a megaplay embed to its CDN master.m3u8 + subtitle tracks."""
        data = await megaplay.fetch_sources_verified(client, mega)
        if not data:
            return {"streams": [], "subtitles": []}

        result = megaplay.build_result(data, mega, server_name)
        if not result["streams"]:
            return result

        file_url = result["streams"][0]["url"]
        referer = result["streams"][0]["referer"]

        if expected_duration and not await self._verify_content(file_url, expected_duration, data, client, referer):
            print(f"AniWatch verify: rejected {server_name} stream (duration mismatch)")
            return {"streams": [], "subtitles": []}

        return result

    async def _verify_content(self, file_url: str, expected_duration: int, data: Dict[str, Any],
                              client: httpx.AsyncClient,
                              referer: str = "https://megaplay.buzz/") -> bool:
        """Reject streams that are clearly the wrong show (corrupted upstream data).

        Conservative rules (calibrated against donghua 11.0min / Punirunes 12.4min
        showing up for Dragon Ball Super ep1, while a legit 69min special must pass):
        - reject if |actual-expected|/expected > 0.35 AND intro is zero AND outro is zero
        - reject if |actual-expected|/expected > 0.35 AND intro is zero AND actual < 15min
        """
        intro = data.get("intro") or {}
        outro = data.get("outro") or {}
        intro_zero = not (intro.get("start") or 0) and not (intro.get("end") or 0)
        outro_zero = not (outro.get("start") or 0) and not (outro.get("end") or 0)

        try:
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Referer": referer,
            }
            resp = await client.get(file_url, headers=headers)
            if resp.status_code != 200:
                return True  # Can't verify -> don't block

            actual = self._playlist_duration(resp.text)
            if not actual:
                # A master playlist carries no EXTINF; follow its first variant.
                variant = self._first_variant(resp.text, file_url)
                if variant:
                    resp2 = await client.get(variant, headers=headers)
                    if resp2.status_code == 200:
                        actual = self._playlist_duration(resp2.text)
        except Exception as e:
            print(f"AniWatch verify: duration check failed ({e})")
            return True

        if not actual:
            return True

        off = abs(actual - expected_duration) / expected_duration
        if off > 0.35 and intro_zero and (outro_zero or actual < 900):
            print(f"AniWatch verify: REJECTED ({actual:.1f}s vs {expected_duration}s expected, off={off:.2f})")
            return False
        return True

    @staticmethod
    def _playlist_duration(text: str) -> float:
        """Total duration of a media playlist, summed from its #EXTINF tags.

        Returns 0.0 for a master playlist (which has no EXTINF entries).
        """
        total = 0.0
        for line in text.splitlines():
            line = line.strip()
            if not line.upper().startswith("#EXTINF:"):
                continue
            value = line.split(":", 1)[1].split(",")[0].strip()
            try:
                total += float(value)
            except ValueError:
                continue
        return total

    @staticmethod
    def _first_variant(text: str, base_url: str) -> str:
        """First variant playlist URI listed in a master playlist."""
        lines = text.splitlines()
        for idx, line in enumerate(lines):
            if not line.strip().upper().startswith("#EXT-X-STREAM-INF"):
                continue
            for candidate in lines[idx + 1:]:
                candidate = candidate.strip()
                if candidate and not candidate.startswith("#"):
                    return urllib.parse.urljoin(base_url, candidate)
        return ""

    def _find_source(self, html: str) -> str:
        match = re.search(r'<source\s+[^>]*src=["\']([^"\']+)["\']', html, re.I)
        if match:
            return match.group(1)
        match = re.search(r'<(?:video|audio)\s+[^>]*src=["\']([^"\']+)["\']', html, re.I)
        if match:
            return match.group(1)
        match = re.search(r'["\'](https?://[^"\']+?\.(?:mp4|webm|mkv))["\']', html, re.I)
        if match:
            return match.group(1)
        return ""

    def _find_m3u8(self, html: str) -> str:
        for pattern in [
            r'["\'](https?://[^"\']+?\.m3u8[^"\']*)["\']',
            r'src\s*[:=]\s*["\']([^"\']+\.m3u8[^"\']*)["\']',
        ]:
            match = re.search(pattern, html, re.I)
            if match:
                return match.group(1)
        return ""