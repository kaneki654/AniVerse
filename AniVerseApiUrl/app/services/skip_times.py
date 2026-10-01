"""
Intro and outro times for any episode, so every anime gets Skip Intro/Outro.

Three sources, best first:

1. Times already found for this exact video (same episode, same length) by the
   fingerprinting below, kept in a small SQLite file.
2. AniSkip (api.aniskip.com), the community database ani-cli and mpv use, keyed
   by MyAnimeList ID. Its entries are for particular releases, so one is only
   used when its episode length matches the video being played; another cut of
   the same episode can be seconds out.
3. Finding them in the audio, the way Jellyfin's intro skipper does: an opening
   song plays in every episode of a season and an ending song likewise, so the
   stretch of audio an episode shares with its neighbour *is* the opening (near
   the start) or the ending (near the end). ffmpeg's chromaprint muxer
   fingerprints both, and the longest run of matching fingerprint points gives
   the times in each episode. One comparison therefore serves two episodes.

Providers that ship their own markers (ZokoAnime, megaplay) attach them to
their streams in the orchestrator; clients only ask here when the stream they
are playing has none.
"""

import asyncio
import re
import sqlite3
import subprocess
import time
from pathlib import Path
from typing import Any

import httpx
import numpy as np

from . import anilist_media

ANISKIP = "https://api.aniskip.com/v2/skip-times/{mal}/{ep}"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

# An AniSkip entry counts as this video when its length is within this much.
LENGTH_TOLERANCE = 2.5

# Chromaprint gives one 32-bit point per 0.1238 s of audio.
POINT = 0.1238
INTRO_WINDOW = 360.0      # openings sit in the first six minutes
OUTRO_WINDOW = 240.0      # endings in the last four
MAX_BIT_DIFF = 6          # points this close count as the same audio
MAX_GAP = 3.5             # a short dropout inside a match does not end it
INTRO_LEN = (15.0, 150.0)
OUTRO_LEN = (15.0, 200.0)
RETRY_AFTER = 7 * 24 * 3600

# Detection downloads video on the same connection the server streams to
# viewers with, so it waits for the player to get ahead and then sips.
START_DELAY = 30.0
RATE_LIMIT = 1_000_000    # bytes per second, about 8 Mbps

_DB = Path(__file__).resolve().parents[2] / "data" / "skip_times.db"
_aniskip_cache: dict[tuple[int, int], tuple[float, list]] = {}
_running: dict[tuple[str, int, str], asyncio.Task] = {}
_detect_gate = asyncio.Semaphore(1)  # one detection at a time: it is bandwidth


# --- storage ---------------------------------------------------------------------------

def _db() -> sqlite3.Connection:
    _DB.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(_DB)
    conn.row_factory = sqlite3.Row
    conn.execute(
        "CREATE TABLE IF NOT EXISTS skip (anilist_id TEXT, episode INTEGER, duration REAL,"
        " intro_start REAL, intro_end REAL, outro_start REAL, outro_end REAL,"
        " checked_at INTEGER, PRIMARY KEY (anilist_id, episode, duration))")
    return conn


def _range(start: Any, end: Any) -> dict[str, int] | None:
    if start is None or end is None or end <= start:
        return None
    return {"start": int(round(start)), "end": int(round(end))}


def _stored(anilist_id: str, episode: int, duration: float) -> sqlite3.Row | None:
    with _db() as conn:
        rows = conn.execute("SELECT * FROM skip WHERE anilist_id = ? AND episode = ?",
                            (anilist_id, episode)).fetchall()
    if duration > 0:
        rows = [r for r in rows if abs(r["duration"] - duration) <= LENGTH_TOLERANCE]
    elif len(rows) != 1:
        return None
    return rows[0] if rows else None


def _store(anilist_id: str, episode: int, duration: float,
           intro: tuple[float, float] | None, outro: tuple[float, float] | None) -> None:
    with _db() as conn:
        old = conn.execute(
            "SELECT * FROM skip WHERE anilist_id = ? AND episode = ? AND ABS(duration - ?) <= ?",
            (anilist_id, episode, duration, LENGTH_TOLERANCE)).fetchone()
        # Keep what an earlier pass found if this one missed it.
        i = intro or ((old["intro_start"], old["intro_end"]) if old and old["intro_start"] is not None else None)
        o = outro or ((old["outro_start"], old["outro_end"]) if old and old["outro_start"] is not None else None)
        if old:
            conn.execute("DELETE FROM skip WHERE anilist_id = ? AND episode = ? AND duration = ?",
                         (anilist_id, episode, old["duration"]))
        conn.execute("INSERT INTO skip VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                     (anilist_id, episode, round(duration, 2), i[0] if i else None, i[1] if i else None,
                      o[0] if o else None, o[1] if o else None, int(time.time())))


# --- AniSkip ------------------------------------------------------------------------------

async def _aniskip(client: httpx.AsyncClient, mal: int, episode: int, duration: float) -> dict[str, Any]:
    key = (mal, episode)
    hit = _aniskip_cache.get(key)
    if hit and time.time() - hit[0] < 12 * 3600:
        results = hit[1]
    else:
        query = "types=op&types=ed&types=mixed-op&types=mixed-ed&episodeLength=0"
        try:
            r = await client.get(f"{ANISKIP.format(mal=mal, ep=episode)}?{query}", timeout=10)
            results = r.json().get("results") or [] if r.status_code in (200, 404) else []
        except (httpx.HTTPError, ValueError):
            return {}
        _aniskip_cache[key] = (time.time(), results)

    found: dict[str, Any] = {}
    for kind, types in (("intro", ("op", "mixed-op")), ("outro", ("ed", "mixed-ed"))):
        best = None
        for r in results:
            if r.get("skipType") not in types:
                continue
            gap = abs(float(r.get("episodeLength") or 0) - duration) if duration > 0 else 0.0
            if duration > 0 and gap > LENGTH_TOLERANCE:
                continue
            if best is None or gap < best[0]:
                best = (gap, r["interval"])
        if best:
            found[kind] = _range(best[1].get("startTime"), best[1].get("endTime"))
    return found


# --- fingerprints ------------------------------------------------------------------------------

async def _media_playlist(client: httpx.AsyncClient, url: str, referer: str) -> tuple[str, list[tuple[str, float]]]:
    """The lowest-bandwidth variant's segments as (url, seconds): only the audio is
    wanted, and every variant carries the same audio."""
    headers = {"Referer": referer, "User-Agent": UA}
    text = (await client.get(url, headers=headers)).text
    if "#EXT-X-STREAM-INF" in text:
        lines = text.splitlines()
        variants = []
        for i, line in enumerate(lines):
            m = re.search(r"BANDWIDTH=(\d+)", line)
            if m and line.startswith("#EXT-X-STREAM-INF") and i + 1 < len(lines):
                variants.append((int(m.group(1)), str(httpx.URL(url).join(lines[i + 1].strip()))))
        if variants:
            url = min(variants)[1]
            text = (await client.get(url, headers=headers)).text
    segments, dur = [], None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#EXTINF:"):
            dur = float(line[8:].split(",")[0])
        elif line and not line.startswith("#") and dur is not None:
            segments.append((str(httpx.URL(url).join(line)), dur))
            dur = None
    return url, segments


async def _fetch_window(client: httpx.AsyncClient, segments: list[tuple[str, float]], referer: str,
                        start: float, length: float) -> tuple[bytes, float]:
    """The segments covering [start, start + length], downloaded in parallel and
    joined (MPEG-TS concatenates), and the time the first one starts at."""
    picked, t, first = [], 0.0, None
    for seg_url, dur in segments:
        if t + dur > start and t < start + length:
            picked.append(seg_url)
            first = t if first is None else first
        t += dur
    gate = asyncio.Semaphore(4)
    headers = {"Referer": referer, "User-Agent": UA}
    began, got = time.monotonic(), 0

    async def one(u: str) -> bytes:
        nonlocal got
        async with gate:
            for _ in range(3):
                try:
                    r = await client.get(u, headers=headers, timeout=30)
                    if r.status_code == 200:
                        got += len(r.content)
                        # Hold the average under RATE_LIMIT.
                        ahead = got / RATE_LIMIT - (time.monotonic() - began)
                        if ahead > 0:
                            await asyncio.sleep(ahead)
                        return r.content
                except httpx.HTTPError:
                    pass
            return b""

    parts = await asyncio.gather(*(one(u) for u in picked))
    return b"".join(parts), first or 0.0


def _chromaprint(ts: bytes) -> np.ndarray:
    if not ts:
        return np.zeros(0, dtype="<u4")
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0", "-vn", "-ac", "1",
         "-f", "chromaprint", "-fp_format", "raw", "-"],
        input=ts, capture_output=True, timeout=180, check=False).stdout
    return np.frombuffer(out[: len(out) // 4 * 4], dtype="<u4")


def _longest_shared(a: np.ndarray, b: np.ndarray, min_len: float, max_len: float) -> tuple[float, float, float] | None:
    """The longest stretch of audio a and b share: (start in a, start in b, length), in seconds."""
    if len(a) < 10 or len(b) < 10:
        return None
    # Candidate alignments from points that match exactly.
    where: dict[int, list[int]] = {}
    for j, v in enumerate(b.tolist()):
        where.setdefault(v, []).append(j)
    votes: dict[int, int] = {}
    for i, v in enumerate(a.tolist()):
        for j in where.get(v, ()):
            votes[i - j] = votes.get(i - j, 0) + 1
    best = None
    tried = set()
    for shift, _ in sorted(votes.items(), key=lambda kv: -kv[1])[:24]:
        for s in (shift - 1, shift, shift + 1):
            if s in tried:
                continue
            tried.add(s)
            lo, hi = max(0, s), min(len(a), len(b) + s)
            if hi - lo < 10:
                continue
            diff = a[lo:hi] ^ b[lo - s:hi - s]
            bits = np.unpackbits(diff.view(np.uint8)).reshape(-1, 32).sum(axis=1)
            idx = np.flatnonzero(bits <= MAX_BIT_DIFF)
            if not len(idx):
                continue
            breaks = np.flatnonzero(np.diff(idx) > int(MAX_GAP / POINT))
            for st, en in zip(np.r_[0, breaks + 1], np.r_[breaks, len(idx) - 1]):
                length = float(idx[en] - idx[st]) * POINT
                if min_len <= length <= max_len and (best is None or length > best[2]):
                    ia = int(idx[st]) + lo
                    best = (ia * POINT, (ia - s) * POINT, length)
    return best


async def _window_print(client, segments, referer, start, length) -> tuple[np.ndarray, float]:
    ts, first = await _fetch_window(client, segments, referer, start, length)
    fp = await asyncio.to_thread(_chromaprint, ts)
    return fp, first


async def _detect(anilist_id: str, episode: int, category: str, server: str) -> None:
    from ..core.orchestrator import orchestrator  # late: the orchestrator imports providers

    await asyncio.sleep(START_DELAY)
    async with _detect_gate, httpx.AsyncClient(follow_redirects=True, timeout=30) as client:
        info = await anilist_media.get_media(client, anilist_id)
        total = info.get("episodes") or 0
        neighbours = [episode + 1, episode - 1] if not total or episode < total else [episode - 1]
        mine = await orchestrator.resolve_episode(anilist_id, episode, category)
        stream = _pick(mine.get("streams") or [], server)
        if not stream:
            return
        other, other_ep = None, 0
        for n in neighbours:
            if n < 1:
                continue
            res = await orchestrator.resolve_episode(anilist_id, n, category)
            other = _pick(res.get("streams") or [], server)
            if other:
                other_ep = n
                break
        if not other:
            return

        ref_a = stream.get("referer") or ""
        ref_b = other.get("referer") or ""
        _, seg_a = await _media_playlist(client, stream["url"], ref_a)
        _, seg_b = await _media_playlist(client, other["url"], ref_b)
        dur_a = sum(d for _, d in seg_a)
        dur_b = sum(d for _, d in seg_b)
        if dur_a < 300 or dur_b < 300:
            return  # a short or a movie: nothing repeats

        found_a: dict[str, tuple[float, float]] = {}
        found_b: dict[str, tuple[float, float]] = {}
        (fa, sa), (fb, sb) = await asyncio.gather(
            _window_print(client, seg_a, ref_a, 0, INTRO_WINDOW),
            _window_print(client, seg_b, ref_b, 0, INTRO_WINDOW))
        hit = await asyncio.to_thread(_longest_shared, fa, fb, *INTRO_LEN)
        if hit:
            found_a["intro"] = (sa + hit[0], sa + hit[0] + hit[2])
            found_b["intro"] = (sb + hit[1], sb + hit[1] + hit[2])
            # Openings are what people skip most: usable before the ending is done.
            _store(anilist_id, episode, dur_a, found_a["intro"], None)
            _store(anilist_id, other_ep, dur_b, found_b["intro"], None)

        (fa, sa), (fb, sb) = await asyncio.gather(
            _window_print(client, seg_a, ref_a, dur_a - OUTRO_WINDOW, OUTRO_WINDOW),
            _window_print(client, seg_b, ref_b, dur_b - OUTRO_WINDOW, OUTRO_WINDOW))
        hit = await asyncio.to_thread(_longest_shared, fa, fb, *OUTRO_LEN)
        if hit:
            found_a["outro"] = (sa + hit[0], sa + hit[0] + hit[2])
            found_b["outro"] = (sb + hit[1], sb + hit[1] + hit[2])

        _store(anilist_id, episode, dur_a, found_a.get("intro"), found_a.get("outro"))
        _store(anilist_id, other_ep, dur_b, found_b.get("intro"), found_b.get("outro"))
        print(f"Skip times: {anilist_id} ep {episode} {found_a} / ep {other_ep} {found_b}")


def _pick(streams: list[dict[str, Any]], server: str) -> dict[str, Any] | None:
    """The stream to analyse: the one being watched if named, else the best HLS one."""
    hls = [s for s in streams if "m3u8" in s.get("url", "")]
    for s in hls:
        if server and s.get("server") == server:
            return s
    return hls[0] if hls else None


# --- the lookup ----------------------------------------------------------------------------------

async def lookup(anilist_id: str, episode: int, duration: float = 0.0,
                 server: str = "", category: str = "sub") -> dict[str, Any]:
    """{intro, outro, source, pending}: times for this video, and whether a
    detection that may fill in what is missing is under way."""
    result: dict[str, Any] = {"intro": None, "outro": None, "source": None, "pending": False}
    row = _stored(anilist_id, episode, duration)
    if row:
        result.update(intro=_range(row["intro_start"], row["intro_end"]),
                      outro=_range(row["outro_start"], row["outro_end"]))
        if result["intro"] or result["outro"]:
            result["source"] = "audio"

    if not (result["intro"] and result["outro"]):
        async with httpx.AsyncClient(follow_redirects=True, headers={"User-Agent": UA}) as client:
            try:
                mal = (await anilist_media.get_media(client, anilist_id)).get("mal_id")
            except (httpx.HTTPError, RuntimeError, ValueError):
                mal = None
            if mal:
                found = await _aniskip(client, int(mal), episode, duration)
                for kind in ("intro", "outro"):
                    if not result[kind] and found.get(kind):
                        result[kind] = found[kind]
                        result["source"] = result["source"] or "aniskip"

    # Find them in the audio, once per video per week, when they are missing or
    # only AniSkip's: its times are for one release, and a 1420 s episode from
    # another source matched its length yet ran 4 s earlier, which would have
    # skipped the first lines after the opening. Episodic shows only -- a movie
    # or a lone special has no neighbour to share an opening with.
    recently = row is not None and time.time() - row["checked_at"] < RETRY_AFTER
    unsure = not (result["intro"] and result["outro"]) or result["source"] == "aniskip"
    episodic = await _episodic(anilist_id)
    if unsure and duration >= 300 and episodic and not recently:
        key = (anilist_id, episode, category)
        task = _running.get(key)
        if task is None or task.done():
            _running[key] = asyncio.create_task(_guarded_detect(anilist_id, episode, category, server))
        result["pending"] = True
    elif (anilist_id, episode, category) in _running and not _running[(anilist_id, episode, category)].done():
        result["pending"] = True
    return result


async def _episodic(anilist_id: str) -> bool:
    try:
        async with httpx.AsyncClient(headers={"User-Agent": UA}) as client:
            info = await anilist_media.get_media(client, anilist_id)
    except (httpx.HTTPError, RuntimeError, ValueError):
        return False
    return info.get("format") not in ("MOVIE", "MUSIC") and info.get("episodes") != 1


async def _guarded_detect(anilist_id: str, episode: int, category: str, server: str) -> None:
    try:
        await asyncio.wait_for(_detect(anilist_id, episode, category, server), timeout=600)
    except Exception as e:  # noqa: BLE001  # pylint: disable=broad-exception-caught
        # A background job: nothing waits on it, so log and record the attempt.
        print(f"Skip times: detection failed for {anilist_id} ep {episode}: {type(e).__name__}: {e}")
