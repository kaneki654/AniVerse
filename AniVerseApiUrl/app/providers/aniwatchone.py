import asyncio
import base64
import json
import re
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, Any, List, Optional

import httpx
import numpy as np
from Crypto.Cipher import AES
from selectolax.parser import HTMLParser

from .base import BaseProvider
from ..services import anilist_media

BYSE_HOSTS = {"gn1r5n.org", "playmogo.com"}
BYSE_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


# ---------------------------------------------------------------------------
# Byse Proof-of-Work solver (custom 256-bit hash, leading-zero-bits target)
# Ported 1:1 from pow-DEJGtdh2.js and vectorized with numpy.
# ---------------------------------------------------------------------------
def _rotl(x, n):
    return ((x << np.uint32(n)) | (x >> np.uint32(32 - n)))


# Cache-sized batch. `r` is N x 512 uint32 -- 2KB per counter -- and every one
# of the 1024 mixing rounds touches all of it, so past ~2048 counters (4MB) the
# working set falls out of L3 and per-counter cost climbs again (measured
# 1.2k/s at N=32768 but 0.8k/s at N=131072). The cap also bounds how long we
# run without looking for a hit: the old code ran counters 1000..8192 as one
# 7193-wide batch, so a nonce whose answer was 1991 still paid for all 7193
# before anything checked -- 93s for a solve that is reachable in about 3.
_POW_BATCH = 2048


def _solve_pow_range(prefix: str, difficulty: int, counter_lo: int, counter_hi: int,
                     stop_event: threading.Event) -> Optional[str]:
    """Solve PoW for counters in [counter_lo, counter_hi). Returns the counter string or None."""
    pbytes = np.frombuffer(prefix.encode(), dtype=np.uint8)
    P = len(pbytes)

    def ye(e0, e1, e2, e3):
        e0[:] = e0 + e1
        e3[:] = _rotl(e3 ^ e0, 16)
        e2[:] = e2 + e3
        e1[:] = _rotl(e1 ^ e2, 12)
        e0[:] = e0 + e1
        e3[:] = _rotl(e3 ^ e0, 8)
        e2[:] = e2 + e3
        e1[:] = _rotl(e1 ^ e2, 7)
        return e0, e1, e2, e3

    # Decade split is required, not an optimisation: the message is the decimal
    # counter appended to the prefix, so every counter in a batch must have the
    # same digit count for `msgs` to be rectangular.
    for L in range(1, 8):
        decade_lo = max(counter_lo, 10 ** (L - 1), 1)
        decade_hi = min(counter_hi, 10 ** L)
        if decade_lo >= decade_hi:
            continue
        for lo in range(decade_lo, decade_hi, _POW_BATCH):
            hi = min(lo + _POW_BATCH, decade_hi)
            N = int(hi - lo)
            counters = np.arange(lo, hi, dtype=np.int64)
            msgs = np.zeros((N, P + L), dtype=np.uint8)
            msgs[:, :P] = pbytes
            tmp = counters.copy()
            for pos in range(L - 1, -1, -1):
                d = tmp % 10
                msgs[:, P + pos] = d + 48
                tmp //= 10

            e0 = np.full(N, 1779033703, dtype=np.uint32)
            e1 = np.full(N, 3144134277, dtype=np.uint32)
            e2 = np.full(N, 1013904242, dtype=np.uint32)
            e3 = np.full(N, 2773480762, dtype=np.uint32)
            for col in range(msgs.shape[1]):
                b = msgs[:, col].astype(np.uint32)
                e0[:] = e0 + b
                e0[:] = _rotl(e0, 7)
                e0, e1, e2, e3 = ye(e0, e1, e2, e3)
            for _ in range(8):
                e0, e1, e2, e3 = ye(e0, e1, e2, e3)

            # Layout stays (N, 512): each counter's 512-word state is contiguous,
            # so the random gather r[i, a[i]] in the mixing loop stays inside one
            # 2KB row. Transposing to (512, N) makes the sequential scans
            # contiguous but turns that gather into a scatter across the whole
            # array -- measured 5x slower, so the original layout is correct.
            r = np.empty((N, 512), dtype=np.uint32)
            for i in range(512):
                e0, e1, e2, e3 = ye(e0, e1, e2, e3)
                np.bitwise_xor(e0, e2, out=r[:, i])

            lr = np.uint32(2654435761)
            hr = np.uint32(2246822519)
            flat = r.reshape(-1)
            base = np.arange(N, dtype=np.intp) * 512
            for _ in range(2):
                for s in range(512):
                    col = r[:, s]
                    a = (col & np.uint32(511)).astype(np.intp)
                    # Flat gather instead of take_along_axis, which allocated an
                    # (N, 1) temporary on every one of these 1024 iterations.
                    c = col + flat[base + a]
                    c = _rotl(c, 13)
                    np.bitwise_xor(c, r[:, (s + 1) & 511] * lr, out=c)
                    r[:, s] = c
                    np.bitwise_xor(e0, c, out=e0)
                    e0, e1, e2, e3 = ye(e0, e1, e2, e3)

            out = np.empty((N, 8), dtype=np.uint32)
            for i in range(8):
                e0, e1, e2, e3 = ye(e0, e1, e2, e3)
                s = e0.copy()
                a = i * 64
                for j in range(64):
                    d = r[:, a + j]
                    np.add(s, d, out=s)
                    s = _rotl(s, 5)
                    np.bitwise_xor(s, d * hr, out=s)
                np.bitwise_xor(s, e2, out=out[:, i])

            z = np.zeros(N, dtype=np.int64)
            for i in range(8):
                col = out[:, i]
                still = z == i * 32
                nz = col != 0
                m = still & nz
                if m.any():
                    # frexp's exponent is exactly bit_length for a positive
                    # integer, replacing a per-element Python int().bit_length()
                    # loop that dominated this step for large batches.
                    bitlens = np.frexp(col[m].astype(np.float64))[1]
                    z[m] = i * 32 + 32 - bitlens
                z[still & ~nz] = i * 32 + 32

            hits = np.nonzero(z >= difficulty)[0]
            if hits.size:
                stop_event.set()
                return str(int(counters[int(hits[0])]))
            if stop_event.is_set():
                return None
    return None


def solve_pow(nonce: str, difficulty: int, workers: int = 3, max_counter: int = 2_000_000,
              deadline: float = 45.0, cancel: Optional[threading.Event] = None) -> Optional[str]:
    """Solve the Byse PoW using parallel numpy batches.

    Bounded on purpose: this is pure CPU work competing with the event loop, so
    it gives up rather than pinning every core indefinitely for one provider.

    `cancel` must be honoured by callers that can be cancelled. asyncio cannot
    stop a thread already running under `to_thread`, so when the orchestrator
    timed a provider out the solver kept burning every core for the rest of its
    deadline. Those orphans stacked up and starved later solves -- in a 24-title
    sweep the first 8 requests got a Byse stream and all 16 after them timed out.
    """
    if difficulty <= 0:
        return "0"
    prefix = nonce + ":"
    stop_event = cancel or threading.Event()
    # Chunk matches _POW_BATCH so each claimed chunk is exactly one batch:
    # work is handed out in the order counters are actually wanted, and no
    # worker sits on a wide range of high counters while the answer is low.
    # Three workers, not six: each holds its own 4MB scratch array, and six
    # of them thrashed L3 against each other for a ~6x slowdown on the one
    # worker that had the winning range.
    chunk = _POW_BATCH
    lo = 1

    def worker():
        local = lo
        while local < max_counter and not stop_event.is_set():
            with _chunk_lock:
                start = _next_chunk[0]
                _next_chunk[0] += chunk
            if start >= max_counter:
                return None
            result = _solve_pow_range(prefix, difficulty, start, min(start + chunk, max_counter), stop_event)
            if result is not None:
                return result
        return None

    _chunk_lock = threading.Lock()
    _next_chunk = [lo]

    # One shared deadline, not one per future: waiting on each of N futures for
    # `deadline` seconds in turn let a hard nonce grind for N x deadline while
    # pinning every core, which starved the rest of the resolve.
    give_up_at = time.monotonic() + deadline
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = [ex.submit(worker) for _ in range(workers)]
        try:
            for fut in futures:
                remaining = give_up_at - time.monotonic()
                if remaining <= 0:
                    break
                try:
                    result = fut.result(timeout=remaining)
                except Exception:
                    continue
                if result is not None:
                    stop_event.set()
                    return result
        finally:
            # Unblock the workers so the pool can actually shut down.
            stop_event.set()
    return None


# ---------------------------------------------------------------------------
# Byse payload decryption (AES-256-GCM, version-based key-part selection)
# ---------------------------------------------------------------------------
_BYSE_KEY_INDEX = {str(n): [n, 31 - n] for n in range(1, 21)}


def _b64u(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def _decrypt_byse_payload(p: Dict[str, Any]) -> Dict[str, Any]:
    parts = p.get("key_parts") or []
    version = str(p.get("version", ""))
    if version in _BYSE_KEY_INDEX:
        idx = _BYSE_KEY_INDEX[version]
        parts = [parts[i - 1] for i in idx if 1 <= i <= len(parts)]
    key = b"".join(_b64u(x) for x in parts)
    iv = _b64u(p["iv"])
    ct = _b64u(p["payload"])
    cipher = AES.new(key, AES.MODE_GCM, nonce=iv)
    plain = cipher.decrypt(ct[:-16])
    cipher.verify(ct[-16:])
    return json.loads(plain.decode("utf-8"))


_pow_semaphore: Optional[asyncio.Semaphore] = None


def _pow_gate() -> asyncio.Semaphore:
    """Process-wide gate around the CPU-bound PoW solve (lazy, loop-bound)."""
    global _pow_semaphore
    if _pow_semaphore is None:
        _pow_semaphore = asyncio.Semaphore(1)
    return _pow_semaphore


class AniWatchOneProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "AniWatchOne"

    @property
    def base_url(self) -> str:
        return "https://aniwatch.one"

    def __init__(self):
        self._byse_cache: Dict[str, Dict[str, Any]] = {}
        self._byse_cache_lock = threading.Lock()

    def _headers(self, referer: str = None) -> Dict[str, str]:
        headers = {
            "User-Agent": BYSE_UA,
            "Accept": "application/json, text/html, */*",
        }
        if referer:
            headers["Referer"] = referer
        return headers

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=25.0, follow_redirects=True) as client:
            try:
                anime_id = await self.map_anime(client, anilist_id, category)
                if not anime_id:
                    return {"error": "Anime not found on AniWatchOne (Mapping failed)"}

                episode_route = await self.get_episode(client, anime_id, episode, anilist_id)
                if not episode_route:
                    return {"error": f"Episode {episode} not found on AniWatchOne"}

                servers = await self.get_servers(client, episode_route, category)
                if not servers:
                    return {"error": "No embed servers found on AniWatchOne"}

                return await self.extract(client, servers)
            except Exception as e:
                return {"error": f"AniWatchOne extraction failed: {str(e)}"}

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str = "sub") -> str:
        """Map AniList ID to the aniwatch.one anime route id (slug-animeId).

        Returns "" unless a result's own title confirms it is the requested show.
        The site answers a miss with its "most popular" block rather than an empty
        page, so an unverified best-guess here plays a random popular anime.
        """
        try:
            info = await anilist_media.get_media(client, anilist_id)
            title_ro = info["title_ro"]
            title_en = info["title_en"]

            titles_to_try = [self.clean_title(title_ro), self.clean_title(title_en)]
            norm_titles = []
            for t in titles_to_try:
                n = self.normalize_title(t)
                if n and n not in norm_titles:
                    norm_titles.append(n)
            if not norm_titles:
                return ""
            want_season = max(self.season_of(title_ro), self.season_of(title_en))
            want_part = max(self.part_of(title_ro), self.part_of(title_en))
            anilist_episodes = info.get("episodes")

            candidates = []
            seen_routes = set()
            seen_keywords = set()

            for t in titles_to_try:
                if not t or t.lower() in seen_keywords:
                    continue
                seen_keywords.add(t.lower())
                search_url = f"{self.base_url}/search?keyword={urllib.parse.quote(t)}"
                search_resp = await client.get(search_url, headers=self._headers())
                if search_resp.status_code != 200:
                    continue
                tree = HTMLParser(search_resp.text)
                # Scope to the results grid: the popular/sidebar blocks live
                # outside it, and a no-result search leaves it empty.
                for item in tree.css('.film_list-wrap .flw-item'):
                    a = item.css_first('a[href*="/watch/"]')
                    if not a:
                        continue
                    href = a.attributes.get("href", "")
                    m = re.search(r'/watch/(.+)-(\d+)$', href)
                    if not m:
                        continue
                    route = href.strip("/")
                    if route in seen_routes:
                        continue
                    seen_routes.add(route)

                    name_el = item.css_first(".film-name a") or item.css_first(".film-name")
                    # The visible name is usually English while AniList may only
                    # supply romaji - the slug carries the romaji, so keep all three.
                    aliases = [
                        (name_el.attributes.get("data-jname") if name_el else "") or "",
                        (name_el.text(strip=True) if name_el else "") or "",
                        m.group(1).replace("-", " "),
                    ]
                    # The card already prints the episode count, which tells the
                    # parts of a season apart without another request.
                    eps_el = item.css_first(".tick-sub") or item.css_first(".tick-item")
                    try:
                        eps = int((eps_el.text(strip=True) if eps_el else "") or 0) or None
                    except ValueError:
                        eps = None
                    candidates.append({
                        "route": route,
                        "aliases": [x for x in aliases if x],
                        "eps": eps,
                    })

            if not candidates:
                print(f"AniWatchOne map: no search results for {norm_titles[0]!r} -> rejected")
                return ""

            def agreeing_part(cand):
                """Part number of the alias that matches, or None if none does."""
                for alias in cand["aliases"]:
                    if self.season_of(alias) != want_season:
                        continue
                    part = self.part_of(alias)
                    # A titled part only answers for the part AniList asked for.
                    if want_part and part != want_part:
                        continue
                    na = self.normalize_title(self.clean_title(alias))
                    if any(self.titles_agree(na, nt) for nt in norm_titles):
                        return part
                return None

            matches = []
            for cand in candidates:
                part = agreeing_part(cand)
                if part is not None:
                    matches.append((cand, part))

            if not matches:
                print(f"AniWatchOne map: no candidate matched {norm_titles[0]!r} "
                      f"(season {want_season}, part {want_part}); "
                      f"{[c['route'] for c in candidates][:4]} -> rejected")
                return ""

            # normalize_title() drops "Part N", so every part of a season matches
            # equally and first-hit order would decide it. Prefer the candidate
            # whose episode count matches AniList, then the part actually asked
            # for (part 0 = the unqualified entry when AniList names none).
            if len(matches) > 1:
                def rank(entry):
                    cand, part = entry
                    exact = anilist_episodes and cand.get("eps") == anilist_episodes
                    return (0 if exact else 1, abs(part - want_part))

                matches.sort(key=rank)
                print(f"AniWatchOne map: {len(matches)} candidates for {norm_titles[0]!r} "
                      f"(want {anilist_episodes} eps) -> "
                      f"{[(c['route'], c.get('eps')) for c, _ in matches[:3]]}")

            return matches[0][0]["route"]
        except Exception as e:
            print(f"AniWatchOne Map error: {type(e).__name__}: {e}")
        return ""

    async def get_episode(self, client: httpx.AsyncClient, anime_id: str, episode_num: int,
                          anilist_id: str = None) -> str:
        """Find the episode route for a given episode number.

        The record page names the anime it belongs to, so this is the last place
        a mapping slip can be caught before a stream is handed back. The episode
        list carries only numbers -- no titles -- so identity is checked at the
        series level here and the number is trusted within the right record.
        """
        try:
            url = f"{self.base_url}/{anime_id}"
            resp = await client.get(url, headers=self._headers())
            if resp.status_code != 200:
                return ""
            tree = HTMLParser(resp.text)

            if anilist_id and not await self._record_is_expected(client, tree, anilist_id, anime_id):
                return ""

            for item in tree.css(".ep-item"):
                if item.attributes.get("data-number") == str(episode_num):
                    href = item.attributes.get("href", "")
                    if href:
                        return href.strip("/")
                    ep_id = item.attributes.get("data-id", "")
                    if ep_id:
                        return f"{anime_id}/episode/{episode_num}"
        except Exception as e:
            print(f"AniWatchOne Episode error: {e}")
        return ""

    async def _record_is_expected(self, client: httpx.AsyncClient, tree, anilist_id: str,
                                  anime_id: str) -> bool:
        """Confirm the record page is the anime AniList asked for."""
        el = tree.css_first(".film-name") or tree.css_first("h2")
        name = el.text(strip=True) if el else ""
        if not name:
            return True  # Nothing to check against; don't reject on absence.

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
        if self.series_matches(name, norm_titles, want_season, want_part):
            return True

        print(f"AniWatchOne verify: {anime_id} is {name!r}, expected {norm_titles[0]!r} "
              f"(season {want_season}, part {want_part}) -> rejected")
        return False

    async def get_servers(self, client: httpx.AsyncClient, episode_route: str, category: str = "sub") -> List[Dict[str, str]]:
        """Scrape the episode page for Byse embed server URLs."""
        servers = []
        try:
            url = f"{self.base_url}/{episode_route}"
            resp = await client.get(url, headers=self._headers())
            if resp.status_code != 200:
                return servers
            tree = HTMLParser(resp.text)
            for item in tree.css(".server-item"):
                data_url = item.attributes.get("data-url", "")
                if not data_url:
                    continue
                servers.append({
                    "name": item.attributes.get("data-id", "Byse"),
                    "type": item.attributes.get("data-type", "sub"),
                    "url": data_url,
                })

            servers = [s for s in servers if s.get("type") == category]
            seen = set()
            unique = []
            for s in servers:
                if s["url"] in seen:
                    continue
                seen.add(s["url"])
                unique.append(s)
            return unique
        except Exception as e:
            print(f"AniWatchOne Servers error: {e}")
            return servers

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        streams = []
        subtitles = []
        seen = set()

        # Each Byse server costs a proof-of-work solve, so the servers share one
        # time budget rather than a fixed attempt count. The old code allowed
        # exactly one attempt because a solve took the full 45s and two of them
        # overran the orchestrator's 60s provider timeout; batch-capping the
        # solver brought a typical solve down to a few seconds, so a second
        # server is now affordable when the first one yields nothing.
        pow_budget_ends = time.monotonic() + 45.0

        for server in servers:
            try:
                embed_url = server["url"]
                host = urllib.parse.urlparse(embed_url).netloc
                if host not in BYSE_HOSTS:
                    continue
                pow_left = pow_budget_ends - time.monotonic()
                if streams or pow_left < 5.0:
                    # Either we already have a stream, or there is not enough
                    # budget left for a solve to plausibly finish.
                    if not streams:
                        print("AniWatchOne: skipping extra PoW server (budget spent)")
                    break
                code = self._embed_code(embed_url)
                if not code:
                    continue
                m3u8 = await self._byse_stream(client, host, code, embed_url, pow_left)
                if not m3u8:
                    continue
                if m3u8 in seen:
                    continue
                seen.add(m3u8)
                streams.append({
                    "quality": "auto",
                    "url": m3u8,
                    "server": server.get("name", "Byse"),
                    "category": server.get("type", "sub"),
                })
            except Exception as e:
                print(f"AniWatchOne Extract Failed ({server.get('name')}): {e}")
                continue

        return {"streams": streams, "subtitles": subtitles}

    @staticmethod
    def _embed_code(embed_url: str) -> str:
        path = urllib.parse.urlparse(embed_url).path.strip("/")
        parts = path.split("/")
        if len(parts) >= 2 and parts[0] in ("e", "d", "embed"):
            return parts[1]
        return parts[-1] if parts else ""

    async def _byse_stream(self, client: httpx.AsyncClient, host: str, code: str,
                           embed_url: str, pow_deadline: float = 45.0) -> Optional[str]:
        """Run the full Byse flow: captcha -> PoW -> verify -> playback -> decrypt -> m3u8."""
        cache_key = f"{host}:{code}"
        with self._byse_cache_lock:
            cached = self._byse_cache.get(cache_key)
            if cached and cached["expires"] > time.time():
                return cached["url"]

        base = f"https://{host}"
        headers = {
            "User-Agent": BYSE_UA,
            "Referer": embed_url,
            "Origin": base,
            "X-Embed-Origin": "https://aniwatch.one",
            "X-Embed-Referer": embed_url,
            "Content-Type": "application/json",
        }
        fingerprint = {}

        try:
            captcha = await client.post(f"{base}/api/videos/{code}/embed/captcha",
                                        headers=headers, json={"fingerprint": fingerprint})
            if captcha.status_code != 200:
                return None
            cj = captcha.json()

            # Serialize the CPU-bound solve. The orchestrator fans out eight
            # provider calls at once; letting each start its own thread pool
            # oversubscribed every core and stalled the whole request.
            # The solver threads outlive a cancelled await, so hand them a flag
            # and set it on the way out however we leave -- success, error or
            # cancellation. Without this every provider timeout leaked a pool of
            # busy CPU threads.
            cancel = threading.Event()
            try:
                async with _pow_gate():
                    solution = await asyncio.to_thread(
                        solve_pow,
                        cj.get("pow_nonce", ""),
                        int(cj.get("pow_difficulty", 0)),
                        3,
                        2_000_000,
                        pow_deadline,
                        cancel,
                    )
            finally:
                cancel.set()
            if solution is None:
                print(f"AniWatchOne: PoW gave up for {host}/{code}")
                return None

            verify = await client.post(f"{base}/api/videos/{code}/embed/captcha/verify",
                                       headers=headers, json={
                                           "pow_token": cj["pow_token"],
                                           "solution": solution,
                                           "fingerprint": fingerprint,
                                       })
            if verify.status_code != 200:
                return None
            vj = verify.json()
            token = vj.get("token")
            if vj.get("status") != "ok" or not token:
                return None

            playback = await client.post(f"{base}/api/videos/{code}/embed/playback",
                                         headers={**headers, "X-Captcha-Token": token},
                                         json={"fingerprint": fingerprint})
            if playback.status_code != 200:
                return None

            payload = playback.json().get("playback")
            if not payload:
                return None
            inner = _decrypt_byse_payload(payload)
            sources = inner.get("sources") or []
            if not sources:
                return None
            url = sources[0].get("url")
            if not url:
                return None

            with self._byse_cache_lock:
                self._byse_cache[cache_key] = {
                    "url": url,
                    "expires": time.time() + 3600,
                }
            return url
        except Exception as e:
            print(f"AniWatchOne Byse flow failed ({host}/{code}): {type(e).__name__}: {e}")
            return None