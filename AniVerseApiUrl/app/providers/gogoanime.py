import httpx
import json
import base64
import re
import urllib.parse
from typing import Dict, Any, List
from selectolax.parser import HTMLParser
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad

from .base import BaseProvider
from ..extractors import megaplay
from ..services import anilist_media

class GogoAnimeProvider(BaseProvider):
    # Ordered by liveness as of the last probe. anitaku.to (dead DNS),
    # anitaku.bz (bad cert) and gogoanime3.co (JS-challenge stub) are kept last
    # so a revival still works, but they no longer block the reachable mirror.
    MIRRORS = [
        "https://www.gogoanime.is",
        "https://ww19.gogoanimes.fi",
        "https://gogoanime3.co",
        "https://anitaku.to",
        "https://anitaku.bz",
    ]

    def __init__(self):
        self._base_url: str = None

    @property
    def name(self) -> str:
        return "GogoAnime"

    @property
    def base_url(self) -> str:
        return self._base_url or self.MIRRORS[0]

    async def _ensure_base(self, client: httpx.AsyncClient) -> str:
        """Pick the first mirror that can actually serve a search, solving its JS challenge if needed.

        Reachability is not enough: several surviving gogo clones answer 200 with
        a full page but expose no /category/ links, so the mirror is accepted
        only once a probe search returns the slugs the rest of the flow needs.
        """
        if self._base_url:
            return self._base_url

        ua = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}

        def origin_of(resp) -> str:
            parts = urllib.parse.urlparse(str(resp.url))
            return f"{parts.scheme}://{parts.netloc}"

        for mirror in self.MIRRORS:
            try:
                # The search endpoint is the capability we actually need, and it
                # follows the mirror's redirects to whatever host is alive today.
                probe = await client.get(
                    f"{mirror}/search.html?keyword={urllib.parse.quote('one piece')}", headers=ua)

                # gogoanime3.co gates behind a JS challenge; solve it and retry once.
                if probe.status_code == 200:
                    m = re.search(r"window\.location\.replace\('([^']+)'\)", probe.text)
                    if m and "ch=1" in m.group(1):
                        rc = await client.get(urllib.parse.urljoin(mirror, m.group(1)), headers=ua)
                        client.cookies.update(rc.cookies)
                        probe = await client.get(
                            f"{mirror}/search.html?keyword={urllib.parse.quote('one piece')}", headers=ua)

                if probe.status_code != 200:
                    print(f"Gogo mirror {mirror} -> HTTP {probe.status_code}, skipped")
                    continue
                if not re.search(r'href="/category/[^"]+"', probe.text):
                    print(f"Gogo mirror {mirror} has no /category links -> skipped")
                    continue

                final = origin_of(probe)
                self._base_url = final
                print(f"Gogo mirror selected: {final}")
                return final
            except Exception as e:
                print(f"Gogo mirror {mirror} failed: {type(e).__name__}")
                continue
        return ""

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            try:
                base = await self._ensure_base(client)
                if not base:
                    return {"error": "No GogoAnime mirror reachable"}
                anime_slug = await self.map_anime(client, anilist_id, category)
                if not anime_slug:
                    return {"error": "Anime not found on GogoAnime (Mapping failed)"}
                    
                episode_id = await self.get_episode(client, anime_slug, episode)
                
                servers = await self.get_servers(client, episode_id, category,
                                                 anilist_id=anilist_id, episode_num=episode)
                if not servers:
                    return {"error": "No embed servers found (Might be Cloudflare blocked)"}
                    
                return await self.extract(client, servers, category)
            except Exception as e:
                return {"error": f"GogoAnime extraction failed: {str(e)}"}

    # Search results tag their audio in the title, e.g. "One Piece (Dub)".
    _DUB_SUFFIX_RE = re.compile(r'\s*\((?:dub|dubbed|english dub)\)\s*$', re.I)

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Resolve the AniList title to a GogoAnime category slug.

        The search returns every loosely-related entry (searching "Dragon Ball"
        leads with Dragon Ball Z), so candidates are matched against the AniList
        title instead of taking the first hit, and a weak match is rejected
        rather than played as the wrong show.
        """
        if not self._base_url:
            # No mirror survived selection; searching would build a "/None/..." URL.
            return ""
        try:
            info = await anilist_media.get_media(client, anilist_id)
            title_ro = info["title_ro"]
            title_en = info["title_en"]

            norm_titles = []
            for t in (title_ro, title_en):
                n = self.normalize_title(self.clean_title(t))
                if n and n not in norm_titles:
                    norm_titles.append(n)
            if not norm_titles:
                return ""
            want_season = max(self.season_of(title_ro), self.season_of(title_en))
            want_part = max(self.part_of(title_ro), self.part_of(title_en))

            candidates = {}
            seen_keywords = set()
            for raw in (title_ro, title_en):
                t = self.clean_title(raw)
                if not t or t.lower() in seen_keywords:
                    continue
                seen_keywords.add(t.lower())
                search_url = f"{self._base_url}/search.html?keyword={urllib.parse.quote(t)}"
                search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                if search_resp.status_code != 200:
                    continue
                for li in HTMLParser(search_resp.text).css(".items li"):
                    a = li.css_first("p.name a")
                    if not a:
                        continue
                    href = a.attributes.get("href", "")
                    m = re.match(r'/category/(.+)$', href)
                    if not m:
                        continue
                    slug = m.group(1)
                    title = (a.attributes.get("title") or a.text(strip=True) or "").strip()
                    candidates.setdefault(slug, title)

            if not candidates:
                return ""

            # Keep only entries whose audio matches what was asked for.
            wanted_dub = category == "dub"
            pool = []
            for slug, title in candidates.items():
                is_dub = bool(self._DUB_SUFFIX_RE.search(title)) or slug.lower().endswith("-dub")
                if is_dub != wanted_dub:
                    continue
                base_title = self._DUB_SUFFIX_RE.sub("", title)
                # A season marker survives here but not in normalize_title, so
                # capture it before the season words are stripped away.
                if self.season_of(base_title) != want_season:
                    continue
                # Same for "Part N": without this every part of a season looks
                # identical and the first search hit wins, which is how season 3
                # ended up playing the Final Season's part 2.
                part = max(self.part_of(base_title), self.part_of(slug.replace("-", " ")))
                if want_part and part != want_part:
                    continue
                pool.append((slug, self.normalize_title(self.clean_title(base_title)), part))

            if not pool:
                return ""

            # When AniList names no part, the unqualified entry is the one it
            # means, so prefer the lowest part number over search order.
            pool.sort(key=lambda e: abs(e[2] - want_part))

            for slug, norm, _part in pool:
                for nt in norm_titles:
                    if self.titles_agree(norm, nt):
                        return slug

            print(f"Gogo map: no candidate matched {norm_titles[0]!r} "
                  f"(season {want_season}, part {want_part}); "
                  f"{[s for s, _, _ in pool][:4]} -> rejected")
            return ""

        except Exception as e:
            print(f"Gogo Search error: {type(e).__name__}: {e}")
        return "" 

    async def get_episode(self, client: httpx.AsyncClient, anime_slug: str, episode_num: int) -> str:
        """Construct the standard Gogoanime episode route"""
        return f"{anime_slug}-episode-{episode_num}"

    _EP_IN_TITLE_RE = re.compile(r'\bepisode\s*(\d+)', re.I)

    async def _page_is_expected(self, client: httpx.AsyncClient, tree, anilist_id: str,
                                episode_num: int, episode_id: str) -> bool:
        """Confirm the episode page is the anime and episode that was requested."""
        heading = tree.css_first(".title_name") or tree.css_first("h1")
        heading = heading.text(strip=True) if heading else ""
        if not heading:
            return True  # Nothing to check against; don't reject on absence.

        # "Death Note Episode 1 English Subbed" -> series name + episode number.
        found_ep = self._EP_IN_TITLE_RE.search(heading)
        if episode_num is not None and found_ep and int(found_ep.group(1)) != int(episode_num):
            print(f"Gogo verify: {episode_id} is episode {found_ep.group(1)}, "
                  f"wanted {episode_num} -> rejected")
            return False

        series = self._EP_IN_TITLE_RE.split(heading)[0]
        series = re.sub(r'\b(english\s+(sub|dub)bed|at\s+gogoanime)\b', '', series, flags=re.I)
        series = self._DUB_SUFFIX_RE.sub("", series).strip(" -:|")
        if not series:
            return True

        try:
            info = await anilist_media.get_media(client, anilist_id)
        except Exception:
            return True
        titles = [t for t in (info.get("title_ro"), info.get("title_en")) if t]
        norm_titles = [self.normalize_title(self.clean_title(t)) for t in titles]
        norm_titles = [t for t in norm_titles if t]
        if not norm_titles:
            return True

        want_season = max(self.season_of(t) for t in titles)
        want_part = max(self.part_of(t) for t in titles)
        if self.series_matches(series, norm_titles, want_season, want_part):
            return True

        print(f"Gogo verify: {episode_id} is {series!r}, expected {norm_titles[0]!r} "
              f"(season {want_season}, part {want_part}) -> rejected")
        return False

    async def get_servers(self, client: httpx.AsyncClient, episode_id: str, category: str = "sub",
                          anilist_id: str = None, episode_num: int = None) -> List[Dict[str, str]]:
        """Scrape the episode page for iframe embed links (Vidstreaming/Goload)"""
        url = f"{self._base_url}/{episode_id}"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}

        try:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []

            tree = HTMLParser(resp.text)

            # The page names the anime and episode it actually is ("Death Note
            # Episode 1 English Subbed"). Check it against what was asked for --
            # a mapping slip lands here as a real page, so without this the
            # wrong episode plays happily.
            if anilist_id and not await self._page_is_expected(
                    client, tree, anilist_id, episode_num, episode_id):
                return []

            servers = []

            # Anitaku recently merged sub and dub into single pages.
            # We need to find the right div based on the category.
            div_class = "type_DUB" if category == "dub" else "type_SUB"
            div = tree.css_first(f"div.{div_class}")
            
            # If the specific category div is not found, fallback to the generic selector
            if div:
                links = div.css("ul li a")
            elif category == "dub" and "-dub-" not in episode_id:
                return []
            else:
                links = tree.css(".anime_muti_link ul li a")
            
            for li in links:
                embed_link = li.attributes.get("data-video")
                server_name = li.text(strip=True).replace("Choose this server", "")
                if embed_link:
                    if embed_link.startswith("//"):
                        embed_link = "https:" + embed_link
                    servers.append({
                        "name": server_name,
                        "url": embed_link
                    })
            return servers
        except Exception:
            return [] 

    @staticmethod
    def _fuzz(a: str, b: str) -> int:
        try:
            from rapidfuzz import fuzz
            return int(fuzz.ratio(a, b))
        except Exception:
            return 100 if a == b else 0

    async def _unwrap_newplayer(self, client: httpx.AsyncClient, embed_url: str):
        """Follow a newplayer.php wrapper to the megaplay-family embed it iframes."""
        try:
            resp = await client.get(embed_url, headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Referer": f"{self._base_url}/",
            })
            if resp.status_code != 200:
                return None
            for src in re.findall(r'<iframe[^>]+src=["\']([^"\']+)', resp.text, re.I):
                mega = megaplay.match_megaplay(src)
                if mega:
                    return mega
        except Exception as e:
            print(f"Gogo newplayer unwrap failed: {e}")
        return None

    def unpack(self, p: str, a: int, c: int, k: list) -> str:
        def to_base(num, base):
            if num == 0: return '0'
            res = ""
            while num > 0:
                rem = num % base
                res = (str(rem) if rem < 10 else chr(rem - 10 + ord('a'))) + res
                num //= base
            return res

        while c > 0:
            c -= 1
            if k[c]:
                word = to_base(c, a)
                p = re.sub(r'\b' + word + r'\b', k[c], p)
        return p

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]], category: str = "sub") -> Dict[str, Any]:
        """
        Extract VibePlayer direct M3U8 streams and subtitles.
        """
        streams = []
        subtitles = []

        for server in servers:
            # gogoanime.is wraps its players in newplayer.php, which is just an
            # iframe around a megaplay/vidwish embed - the same getSources API
            # AniWatch uses. Resolve it through the shared extractor.
            mega = megaplay.match_megaplay(server["url"])
            if not mega and "newplayer.php" in server["url"]:
                mega = await self._unwrap_newplayer(client, server["url"])
            if mega:
                try:
                    data = await megaplay.fetch_sources_verified(client, mega)
                    if not data:
                        continue
                    result = megaplay.build_result(data, mega, server.get("name", "Megaplay"))
                    if not result["streams"]:
                        continue
                    stream = result["streams"][0]
                    if not await megaplay.check_playable(client, stream["url"], stream["referer"]):
                        print(f"Gogo: {mega['api_host']} stream not playable -> skipped")
                        continue
                    streams.append(stream)
                    subtitles.extend(result["subtitles"])
                except Exception as e:
                    print(f"Gogo Megaplay Extraction Failed: {e}")
                continue

            if "vibeplayer" in server["url"]:
                try:
                    embed_url = server["url"]
                    parsed = urllib.parse.urlparse(embed_url)
                    video_id = parsed.path.strip("/")
                    
                    # VibePlayer exposes the master playlist directly
                    master_url = f"https://vibeplayer.site/public/stream/{video_id}/master.m3u8"
                    streams.append({
                        "quality": "auto",
                        "url": master_url,
                        "server": server.get("name", "VibePlayer"),
                        "category": category,
                    })
                    
                    # Extract subtitle from query params
                    params = urllib.parse.parse_qs(parsed.query)
                    subs = params.get('sub', [])
                    if subs:
                        subtitles.append({
                            "file": subs[0],
                            "label": "English",
                            "kind": "captions"
                        })
                        
                    # Also try to extract multiple captions from caption_1, caption_2 etc
                    for key, val in params.items():
                        if key.startswith('caption_'):
                            idx = key.split('_')[1]
                            lang = params.get(f'sub_{idx}', ['English'])[0]
                            subtitles.append({
                                "file": val[0],
                                "label": lang,
                                "kind": "captions"
                            })
                    
                    # For dubs, we don't expect subtitles, so don't continue if empty.
                    if not subtitles and category == "sub":
                        continue
                    break # Success!
                    
                except Exception as e:
                    print(f"VibePlayer Extraction Failed: {e}")
                    continue

            elif "otakuhg" in server["url"] or "streamhg" in server["name"].lower():
                try:
                    embed_url = server["url"]
                    r = await client.get(embed_url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                    match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
                    if match:
                        p = match.group(1).replace('\\\'', "'")
                        a = int(match.group(2))
                        c = int(match.group(3))
                        k = match.group(4).split('|')
                        
                        unpacked = self.unpack(p, a, c, k)
                        m3u8_links = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
                        if m3u8_links:
                            streams.append({
                                "quality": "auto",
                                "url": m3u8_links[0],
                                "server": server.get("name", "StreamHG"),
                                "category": category,
                            })
                            
                            parsed = urllib.parse.urlparse(embed_url)
                            params = urllib.parse.parse_qs(parsed.query)
                            subs = params.get('sub', [])
                            if subs:
                                subtitles.append({
                                    "file": subs[0],
                                    "label": "English",
                                    "kind": "captions"
                                })
                            for key, val in params.items():
                                if key.startswith('caption_'):
                                    idx = key.split('_')[1]
                                    lang = params.get(f'sub_{idx}', ['English'])[0]
                                    subtitles.append({
                                        "file": val[0],
                                        "label": lang,
                                        "kind": "captions"
                                    })
                            if not subtitles and category == "sub":
                                continue
                            # Do NOT break for otakuhg/premilkyway because they are Cloudflare IP-locked.
                            # We want to continue scanning servers so we can find Doodstream as a fallback!
                            continue
                except Exception as e:
                    print(f"OtakuHG Extraction Failed: {e}")
                    continue

            elif "dood" in server["url"] or "vidplay" in server["url"]:
                try:
                    embed_url = server["url"]
                    import random
                    import string
                    import time
                    import asyncio
                    
                    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
                    r = await client.get(embed_url, headers=headers)
                    if r.status_code == 200:
                        match = re.search(r"(/pass_md5/[^']*)", r.text)
                        if match:
                            pass_md5_url = "https://" + urllib.parse.urlparse(embed_url).netloc + match.group(1)
                            token = pass_md5_url.split("/")[-1]
                            
                            await asyncio.sleep(1) # Bypass doodstream simple ratelimit
                            r2 = await client.get(pass_md5_url, headers={"User-Agent": headers["User-Agent"], "Referer": embed_url})
                            
                            if r2.status_code == 200:
                                base_url = r2.text
                                random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
                                expiry = str(int(time.time() * 1000))
                                final_url = f"{base_url}{random_str}?token={token}&expiry={expiry}"
                                
                                streams.append({
                                    "quality": "auto",
                                    "url": final_url,
                                    "server": server.get("name", "Doodstream"),
                                    "category": category,
                                })
                                break # Doodstream worked
                except Exception as e:
                    print(f"Doodstream Extraction Failed: {e}")
                    continue

                    
        return {"streams": streams, "subtitles": subtitles}
