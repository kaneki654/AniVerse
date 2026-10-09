"""
Tagalog dubs: the official ones, from the Philippine licensees' YouTube
channels (Muse Philippines, Ani-One Philippines).

They are free and legal to watch there, and may be embedded -- in the
Philippines only, which is where they are licensed. AniVerse plays them in
YouTube's own embedded player, so the views and the ads stay with the channel;
nothing is downloaded or proxied.

- app/tagalog_dubs.json is the catalogue, built by scripts/find_tagalog_dubs.py:
  per show, the channel's episode videos and which AniList entry covers which
  of the channel's episode numbers (the channels number straight through the
  seasons; AniList splits them).
- Some dubs are only up as one long "full marathon" video a season. Those
  episodes are clips of it -- "clips": {episode: [start, end]} in seconds,
  from the video's own chapters -- and play just that part.
- New weekly episodes of those shows are picked up from the channels' official
  RSS feeds every few hours (data/tagalog_new.json), each checked to be free to
  watch -- not an early "members only" upload.
"""

import asyncio
import html
import json
import re
import threading
import time
from pathlib import Path
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from app import accounts

CATALOGUE = Path(__file__).resolve().parent / "tagalog_dubs.json"
REFRESH_EVERY = 6 * 3600
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)", "Accept-Language": "en"}

router = APIRouter()

_lock = threading.Lock()
_catalogue: dict[str, Any] | None = None


def _new_path() -> Path:
    return accounts.DATA_DIR / "tagalog_new.json"


def _load() -> dict[str, Any]:
    global _catalogue
    with _lock:
        if _catalogue is None:
            try:
                _catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
        if not isinstance(_catalogue, dict):
            _catalogue = {"shows": [], "channels": {}, "region": ["PH"]}
        return _catalogue


def _found_since() -> dict[str, dict[str, str]]:
    try:
        data = json.loads(_new_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _episodes(show: dict[str, Any]) -> dict[str, str]:
    """The channel's episode number -> video, catalogue plus what RSS added."""
    return {**show.get("episodes", {}), **_found_since().get(show["key"], {})}


def reset() -> None:
    """For tests: read the catalogue again."""
    global _catalogue
    with _lock:
        _catalogue = None


def for_anime(anilist_id: int) -> dict[str, Any] | None:
    """{title, channel, channelUrl, region, episodes: {anilist episode: video id}}, or None.
    A show cut from marathon videos also has clips: {anilist episode: [start, end]}."""
    cat = _load()
    for show in cat.get("shows", []):
        for season in show.get("seasons", []):
            if season.get("anilist") != anilist_id:
                continue
            channel_eps = _episodes(show)
            first, last = int(season["first"]), int(season["last"])
            episodes = {str(n - first + 1): channel_eps[str(n)] for n in range(first, last + 1) if str(n) in channel_eps}
            if not episodes:
                return None
            ch = cat.get("channels", {}).get(show["channel"], {})
            found = {
                "anilist": anilist_id,
                "title": show.get("title", ""),
                "channel": ch.get("name", ""),
                "channelUrl": f"https://www.youtube.com/channel/{ch['id']}" if ch.get("id") else "",
                "region": cat.get("region", ["PH"]),
                "episodes": episodes,
            }
            clips = show.get("clips", {})
            if clips:
                found["clips"] = {str(n - first + 1): clips[str(n)] for n in range(first, last + 1) if str(n) in clips}
            return found
    return None


def anime_ids() -> list[int]:
    return [s["anilist"] for show in _load().get("shows", []) for s in show.get("seasons", [])
            if for_anime(s["anilist"])]


# --- poster data for the "Tagalog dub" row --------------------------------------------------

_media_cache: tuple[float, list] = (0.0, [])
_MEDIA_QUERY = """query ($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) {
  id title { english romaji } coverImage { large } averageScore episodes status format seasonYear } } }"""


async def _media(ids: list[int]) -> list[dict]:
    global _media_cache
    if time.time() - _media_cache[0] < 12 * 3600 and _media_cache[1]:
        return _media_cache[1]
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            r = await client.post("https://graphql.anilist.co", json={"query": _MEDIA_QUERY, "variables": {"ids": ids}})
            media = r.json()["data"]["Page"]["media"] if r.status_code == 200 else []
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        media = []
    if media:
        order = {i: n for n, i in enumerate(ids)}
        media.sort(key=lambda m: order.get(m["id"], 999))
        _media_cache = (time.time(), media)
    return media


@router.get("/api/tagalog")
async def tagalog_list():
    """Every anime with an official Tagalog dub here, as poster cards, and how
    many of its episodes are dubbed."""
    ids = anime_ids()
    media = await _media(ids)
    counts = {i: len((for_anime(i) or {}).get("episodes", {})) for i in ids}
    known = {m["id"] for m in media}
    return {
        "region": _load().get("region", ["PH"]),
        "media": [{**m, "tagalogEpisodes": counts.get(m["id"], 0)} for m in media]
                 + [{"id": i, "tagalogEpisodes": counts[i]} for i in ids if i not in known],
    }


@router.get("/api/tagalog/{anilist_id}")
def tagalog_for(anilist_id: int):
    found = for_anime(anilist_id)
    if not found:
        raise HTTPException(status_code=404, detail="No Tagalog dub for this anime")
    return found


# --- the player page (the app shows it in a web view) -------------------------------------------

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="referrer" content="strict-origin-when-cross-origin">
<title>__TITLE__</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; color: #f2e8d5; font: 14px/1.4 sans-serif; overflow: hidden; }
  #player { position: fixed; inset: 0; width: 100%; height: 100%; border: 0; }
  #note { position: fixed; inset: 0; display: none; align-items: center; justify-content: center; text-align: center; padding: 24px; }
</style></head>
<body>
<div id="player"></div>
<div id="note"></div>
<script>
  // Tells the app (a JavaScriptChannel named "AniVerse") or a parent page
  // where playback is, so watch history keeps working.
  function tell(m) {
    var s = JSON.stringify(m);
    try { if (window.AniVerse) window.AniVerse.postMessage(s); } catch (e) {}
    try { if (window.parent !== window) window.parent.postMessage(m, "*"); } catch (e) {}
  }
  // base/end: where this episode is in a marathon video (0/0: the whole video).
  var player, start = __START__, base = __BASE__, end = __END__, done = false;
  function ended() { if (!done) { done = true; tell({ type: "ended" }); } }
  function onYouTubeIframeAPIReady() {
    var vars = { autoplay: 1, playsinline: 1, rel: 0, start: base + start, origin: location.origin };
    if (end) vars.end = end;
    player = new YT.Player("player", {
      videoId: "__VIDEO__",
      playerVars: vars,
      events: {
        onReady: function () { player.playVideo(); tell({ type: "ready" }); },
        onStateChange: function (e) { if (e.data === 0) ended(); },
        onError: function (e) {
          var note = document.getElementById("note");
          note.style.display = "flex";
          note.textContent = (e.data === 101 || e.data === 150 || e.data === 100)
            ? "This Tagalog dub can't play here. The channel licenses it for the Philippines only."
            : "YouTube couldn't play this video (error " + e.data + ").";
          tell({ type: "error", code: e.data });
        },
      },
    });
  }
  setInterval(function () {
    if (!player || !player.getCurrentTime) return;
    var now = player.getCurrentTime();
    if (end && now >= end) { player.pauseVideo(); ended(); }
    tell({ type: "progress", t: Math.max(0, Math.min(now, end || now) - base),
           d: end ? end - base : player.getDuration(), playing: player.getPlayerState() === 1 });
  }, 5000);
</script>
<script src="https://www.youtube.com/iframe_api"></script>
</body></html>"""


def _clip(found: dict[str, Any] | None, episode: int) -> tuple[int, int]:
    """(start, end) of the episode in its marathon video; (0, 0) for a video of its own."""
    clip = (found or {}).get("clips", {}).get(str(episode))
    try:
        start, end = int(clip[0]), int(clip[1])  # type: ignore[index]
    except (TypeError, ValueError, IndexError):
        return 0, 0
    return (start, end) if 0 <= start < end else (0, 0)


@router.get("/tagalog/{anilist_id}/{episode}", response_class=HTMLResponse)
def tagalog_page(anilist_id: int, episode: int, start: int = 0):
    found = for_anime(anilist_id)
    video = (found or {}).get("episodes", {}).get(str(episode))
    if not video or not re.fullmatch(r"[A-Za-z0-9_-]{6,20}", video):
        raise HTTPException(status_code=404, detail="No Tagalog dub for this episode")
    title = html.escape(f"{(found or {}).get('title', '')} · EP {episode} · Tagalog")
    base, end = _clip(found, episode)
    page = (_PAGE.replace("__TITLE__", title).replace("__VIDEO__", video)
            .replace("__START__", str(max(0, min(start, 6 * 3600))))
            .replace("__BASE__", str(base)).replace("__END__", str(end)))
    return HTMLResponse(page, headers={"Cache-Control": "no-store"})


# --- new weekly episodes, from the channels' official RSS ------------------------------------------

def _watchable(page: str) -> bool:
    m = re.search(r'"playabilityStatus":\{"status":"([A-Z_]+)"', page)
    return bool(m) and m.group(1) == "OK"


async def refresh_once(client: httpx.AsyncClient) -> int:
    """Adds episodes the channels have uploaded since the catalogue was built."""
    cat = _load()
    added = 0
    found = _found_since()
    for key, channel in cat.get("channels", {}).items():
        try:
            r = await client.get(f"https://www.youtube.com/feeds/videos.xml?channel_id={channel['id']}")
        except httpx.HTTPError:
            continue
        if r.status_code != 200:
            continue
        ids = re.findall(r"<yt:videoId>([^<]+)</yt:videoId>", r.text)
        titles = [html.unescape(t) for t in re.findall(r"<title>([^<]+)</title>", r.text)[1:]]
        for video, title in zip(ids, titles):
            for show in cat.get("shows", []):
                # Marathon-cut shows have no per-episode uploads to look for.
                if show.get("channel") != key or not show.get("pattern"):
                    continue
                m = re.search(show["pattern"], title, re.I)
                if not m:
                    continue
                ep = m.group(1) if m.groups() else "1"
                ep = str(int(ep))
                if ep in _episodes(show) or ep in found.get(show["key"], {}):
                    continue
                try:  # not an early members-only upload
                    page = await client.get(f"https://www.youtube.com/watch?v={video}", headers=UA)
                except httpx.HTTPError:
                    continue
                if _watchable(page.text):
                    found.setdefault(show["key"], {})[ep] = video
                    added += 1
    if added:
        path = _new_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(found, indent=1), encoding="utf-8")
        tmp.replace(path)
    return added


async def refresh_loop():
    await asyncio.sleep(90)
    while True:
        try:
            async with httpx.AsyncClient(timeout=30, headers=UA, follow_redirects=True) as client:
                n = await refresh_once(client)
            if n:
                print(f"Tagalog dubs: {n} new episode(s) from the channels' feeds", flush=True)
        except Exception as e:  # noqa: BLE001 - a background check must never stop the server
            print(f"Tagalog dub refresh failed: {e}", flush=True)
        await asyncio.sleep(REFRESH_EVERY)
