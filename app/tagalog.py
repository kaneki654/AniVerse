"""
Tagalog dubs, from the Filipino anime sites that have them, played in
AniVerse's own player like the sub and dub streams.

- app/tagalog_sites.json, built by scripts/find_tagalog_sites.py: per AniList
  id, which episodes each site has -- Senpai Tambayan's are plain .mp4 links
  (archive.org, file.garden), Anime Revival's are episode pages.
- /api/source?category=tl (app/main.py) answers with source_answer(): the
  episode's streams, best first. An Anime Revival episode page holds a plain
  .mp4 (played directly) or a Blogger video, whose token is turned into Google
  video links when the episode is played. Those links only work from the
  address that asked for them, so they go through /proxy/stream.
- /api/tagalog lists the shows (the Home row, the show page's button).
- /tagalog/{id}/{episode}: a bare player page for the 1.12 app, which showed
  the Tagalog dub in a web view.
"""

import json
import re
import threading
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from app import proxy_hosts

CATALOGUE = Path(__file__).resolve().parent / "tagalog_sites.json"
# The same browser as app.main.USER_AGENT, which /proxy/stream fetches with:
# Google's video links only open for the browser that asked for them.
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"}
REVIVAL = "https://animerevival.xyz/episodes/"
BLOGGER_RPC = ("https://www.blogger.com/_/BloggerVideoPlayerUi/data/batchexecute"
               "?rpcids=WcwnYd&source-path=%2Fvideo.g&hl=en&rt=c")
# Blogger's formats, best first; 13 is a tiny 3GP, kept only when there is nothing else.
ITAGS = {37: "1080p", 22: "720p", 18: "360p", 13: "144p"}
LINK_TTL = 3600  # Google's links last about six hours; ask again well before

router = APIRouter()

_lock = threading.Lock()
_catalogue: dict[str, Any] | None = None
_links: dict[str, tuple[float, list[dict]]] = {}


def _load() -> dict[str, Any]:
    global _catalogue
    with _lock:
        if _catalogue is None:
            try:
                _catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
        if not isinstance(_catalogue, dict):
            _catalogue = {"sites": {}, "anime": {}}
        return _catalogue


def reset() -> None:
    """For tests: read the catalogue again, forget the resolved links."""
    global _catalogue
    with _lock:
        _catalogue = None
    _links.clear()


def for_anime(anilist_id: int) -> dict[str, Any] | None:
    """{anilist, title, sites: [names], episodes: {episode: "senpai+revival"}}, or None."""
    cat = _load()
    entry = cat.get("anime", {}).get(str(anilist_id))
    if not entry or not entry.get("episodes"):
        return None
    names = cat.get("sites", {})
    keys = sorted({k for refs in entry["episodes"].values() for k in refs})
    sites = [names.get(k, {}).get("name", k) for k in keys]
    return {
        "anilist": anilist_id,
        "title": entry.get("title", ""),
        "sites": sites,
        "channel": " / ".join(sites),  # what the 1.12 app shows as the source
        "episodes": {ep: "+".join(refs) for ep, refs in entry["episodes"].items()},
    }


def anime_ids() -> list[int]:
    return [int(i) for i, a in _load().get("anime", {}).items() if a.get("episodes")]


# --- playing an episode ---------------------------------------------------------------------------

def page_videos(page: str) -> tuple[list[str], list[str]]:
    """What an Anime Revival episode page plays: (plain .mp4 links, Blogger
    video tokens). Its other hosts -- Abyss, whose links are encrypted, and
    dead Drive / Dailymotion / ok.ru embeds -- give nothing; the catalogue
    leaves out shows that use them (scripts/find_tagalog_sites.py)."""
    # A plain .mp4 in a video.js player or straight in the player's frame.
    mp4s = re.findall(r'<(?:source|iframe)[^>]+src="(https://[^"]+\.mp4)"', page)
    tokens = re.findall(r"blogger\.com/video\.g\?token=([A-Za-z0-9_-]+)", page)
    return list(dict.fromkeys(mp4s)), list(dict.fromkeys(tokens))


async def _revival_links(client: httpx.AsyncClient, slug: str) -> list[dict]:
    """An Anime Revival episode -> its videos, best first: {url, quality, direct}."""
    hit = _links.get(slug)
    if hit and time.time() - hit[0] < LINK_TTL:
        return hit[1]
    page = (await client.get(f"{REVIVAL}{quote(slug)}/", headers=UA)).text
    mp4_links, tokens = page_videos(page)
    mp4s = [{"url": u, "quality": "SD", "direct": True} for u in mp4_links]
    found: list[dict] = []
    for token in tokens:
        req = json.dumps([[["WcwnYd", json.dumps([token, "", 0]), None, "generic"]]])
        r = await client.post(BLOGGER_RPC, data={"f.req": req}, headers=UA)
        for line in r.text.splitlines():
            if not line.startswith("[["):
                continue
            try:
                reply = json.loads(line)[0]
                if reply[:2] != ["wrb.fr", "WcwnYd"]:
                    continue
                streams = json.loads(reply[2])[2] or []
            except (ValueError, IndexError, TypeError):
                continue
            for item in streams:
                try:
                    url, itag = item[0], int(item[1][0])
                except (IndexError, TypeError, ValueError):
                    continue
                if itag in ITAGS and url.startswith("https://"):
                    found.append({"url": url, "itag": itag})
    found.sort(key=lambda s: list(ITAGS).index(s["itag"]))
    if any(s["itag"] != 13 for s in found):
        found = [s for s in found if s["itag"] != 13]
    links = mp4s + [{"url": s["url"], "quality": ITAGS[s["itag"]], "direct": False} for s in found]
    if links:
        _links[slug] = (time.time(), links)
    return links


def _new_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(timeout=20, follow_redirects=True)


async def sources(anilist_id: int, episode: int, client: httpx.AsyncClient | None = None) -> list[dict]:
    """The episode's Tagalog streams, best first: {url, quality, server, direct}."""
    refs = (_load().get("anime", {}).get(str(anilist_id)) or {}).get("episodes", {}).get(str(episode), {})
    names = _load().get("sites", {})
    out: list[dict] = []
    if refs.get("senpai"):
        out.append({"url": refs["senpai"], "quality": "480p", "direct": True,
                    "server": names.get("senpai", {}).get("name", "senpai")})
    if refs.get("revival"):
        own = client is None
        client = client or _new_client()
        try:
            for link in await _revival_links(client, refs["revival"]):
                out.append({**link, "server": names.get("revival", {}).get("name", "revival")})
        except httpx.HTTPError as e:
            print(f"Tagalog: Anime Revival {refs['revival']}: {type(e).__name__}", flush=True)
        finally:
            if own:
                await client.aclose()
    return out


def _playable(stream: dict) -> str:
    if stream["direct"]:
        return stream["url"]
    proxy_hosts.allow(stream["url"])
    return f"/proxy/stream?url={quote(stream['url'], safe='')}&referer={quote('https://www.blogger.com/', safe='')}"


async def source_answer(anilist_id: int, episode: int) -> dict:
    """/api/source's answer for category=tl."""
    streams = await sources(anilist_id, episode)
    found = [{"url": _playable(s), "isM3U8": False, "quality": s["quality"], "serverName": s["server"],
              "subtitles": [], "intro": None, "outro": None} for s in streams]
    return {"data": {
        "sources": found, "subtitles": [], "headers": {}, "hasDub": None, "intro": None, "outro": None,
        "error": None if found else "No Tagalog dub of this episode could be reached right now.",
    }}


# --- the "Tagalog dub" row and the show page's button ---------------------------------------------

_media_cache: tuple[float, list] = (0.0, [])
_MEDIA_QUERY = """query ($ids: [Int], $page: Int) { Page(page: $page, perPage: 50) { media(id_in: $ids, type: ANIME) {
  id title { english romaji } coverImage { large } averageScore popularity episodes status format seasonYear } } }"""


async def _media(ids: list[int]) -> list[dict]:
    global _media_cache
    if time.time() - _media_cache[0] < 12 * 3600 and _media_cache[1]:
        return _media_cache[1]
    media: list[dict] = []
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            for page in range(1, (len(ids) + 49) // 50 + 1):
                r = await client.post("https://graphql.anilist.co", json={
                    "query": _MEDIA_QUERY, "variables": {"ids": ids, "page": page}})
                if r.status_code != 200:
                    break
                media += r.json()["data"]["Page"]["media"]
    except (httpx.HTTPError, ValueError, KeyError, TypeError):
        pass
    if media:
        media.sort(key=lambda m: -(m.get("popularity") or 0))
        _media_cache = (time.time(), media)
    return media


@router.get("/api/tagalog")
async def tagalog_list():
    """Every anime with a Tagalog dub here, most popular first, as poster
    cards, and how many of its episodes are dubbed."""
    ids = anime_ids()
    media = await _media(ids)
    counts = {i: len((for_anime(i) or {}).get("episodes", {})) for i in ids}
    known = {m["id"] for m in media}
    return {
        "media": [{**m, "tagalogEpisodes": counts[m["id"]]} for m in media if m["id"] in counts]
                 + [{"id": i, "tagalogEpisodes": counts[i]} for i in ids if i not in known],
    }


@router.get("/api/tagalog/{anilist_id}")
def tagalog_for(anilist_id: int):
    found = for_anime(anilist_id)
    if not found:
        raise HTTPException(status_code=404, detail="No Tagalog dub for this anime")
    return found


# --- the 1.12 app's player page ---------------------------------------------------------------------

_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>__TITLE__</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  video { position: fixed; inset: 0; width: 100%; height: 100%; background: #000; }
</style></head>
<body>
<video id="v" controls autoplay playsinline></video>
<script>
  // Tells the app (a JavaScriptChannel named "AniVerse") where playback is,
  // so watch history keeps working.
  function tell(m) {
    try { if (window.AniVerse) window.AniVerse.postMessage(JSON.stringify(m)); } catch (e) {}
    try { if (window.parent !== window) window.parent.postMessage(m, "*"); } catch (e) {}
  }
  var urls = __URLS__, start = __START__, at = 0, v = document.getElementById("v");
  function next() {  // the next stream, when one will not play
    if (at >= urls.length) { tell({ type: "error", code: 0 }); return; }
    v.src = urls[at++];
  }
  v.addEventListener("error", next);
  v.addEventListener("loadedmetadata", function () { if (start) { v.currentTime = start; start = 0; } });
  v.addEventListener("ended", function () { tell({ type: "ended" }); });
  setInterval(function () {
    if (v.duration > 0) tell({ type: "progress", t: v.currentTime, d: v.duration, playing: !v.paused });
  }, 5000);
  next();
</script>
</body></html>"""


@router.get("/tagalog/{anilist_id}/{episode}", response_class=HTMLResponse)
async def tagalog_page(anilist_id: int, episode: int, start: int = 0):
    streams = await sources(anilist_id, episode)
    if not streams:
        raise HTTPException(status_code=404, detail="No Tagalog dub for this episode")
    title = f"{(for_anime(anilist_id) or {}).get('title', '')} · EP {episode} · Tagalog"
    urls = json.dumps([_playable(s) for s in streams]).replace("</", "<\\/")
    page = (_PAGE.replace("__TITLE__", title.replace("&", "&amp;").replace("<", "&lt;"))
            .replace("__URLS__", urls).replace("__START__", str(max(0, min(start, 6 * 3600)))))
    return HTMLResponse(page, headers={"Cache-Control": "no-store"})
