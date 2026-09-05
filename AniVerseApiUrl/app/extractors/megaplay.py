"""Shared extractor for the megaplay-family embeds.

megaplay.buzz, vidwish.live and the `*/megaplay/stream/...` proxies all expose
the same `stream/getSources?id=<id>&type=<sub|dub>` endpoint. AniWatch reaches
them through its base64 `data-hash` server links, GogoAnime through a
`newplayer.php` wrapper that iframes the same embed.

Each host token-locks its CDN to its *own* Referer, so the resolved stream
carries the referer that unlocks it rather than a hardcoded one.
"""

import re
import urllib.parse
from typing import Any, Dict, Optional

import httpx

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

# Hosts that serve the megaplay getSources API directly.
NATIVE_HOSTS = ("megaplay.buzz", "vidwish.live")

# .../stream/s-2/<id>/<sub|dub>  — optionally behind a /megaplay/ or /mp/ proxy path.
EMBED_RE = re.compile(
    r'https?://(?P<host>[^/]+)/(?:[^/]+/)*?stream/s-\d+/(?P<id>\d+)/(?P<type>sub|dub)\b',
    re.I,
)


def match_megaplay(embed_url: str) -> Optional[Dict[str, str]]:
    """Return {host, api_host, id, type} for a megaplay-family embed, else None."""
    m = EMBED_RE.search(embed_url or "")
    if not m:
        return None
    host = m.group("host").lower()

    # A proxy host (e.g. 1anime.site/megaplay/...) still talks to megaplay.buzz.
    api_host = host
    if not any(host.endswith(h) for h in NATIVE_HOSTS):
        path = urllib.parse.urlparse(embed_url).path.lower()
        api_host = "vidwish.live" if "vidwish" in path else "megaplay.buzz"

    return {"host": host, "api_host": api_host, "id": m.group("id"), "type": m.group("type").lower()}


async def fetch_sources(client: httpx.AsyncClient, mega: Dict[str, str]) -> Optional[Dict[str, Any]]:
    """Call getSources on the embed's own host. Returns the raw JSON payload."""
    api_host = mega["api_host"]
    eid, cat = mega["id"], mega["type"]
    url = f"https://{api_host}/stream/getSources?id={eid}&type={cat}"
    try:
        resp = await client.get(url, headers={
            "User-Agent": UA,
            "Referer": f"https://{api_host}/stream/s-2/{eid}/{cat}",
            "X-Requested-With": "XMLHttpRequest",
        })
    except Exception as e:
        print(f"Megaplay getSources failed ({api_host}/{eid}/{cat}): {e}")
        return None
    if resp.status_code != 200:
        return None
    try:
        return resp.json()
    except Exception:
        return None


def _file_of(data: Dict[str, Any]) -> Optional[str]:
    sources = (data or {}).get("sources") or {}
    return sources.get("file") if isinstance(sources, dict) else None


async def fetch_sources_verified(client: httpx.AsyncClient, mega: Dict[str, str]) -> Optional[Dict[str, Any]]:
    """getSources, but a dub request must return audio that differs from the sub.

    Several catalogue entries expose a `-dub` route whose embed still resolves
    to the sub file; getSources happily echoes `type=dub` back. Serving that
    would label sub audio as a dub, so cross-check and drop it instead.
    """
    data = await fetch_sources(client, mega)
    if not data:
        return None

    if mega.get("type") == "dub":
        file_url = _file_of(data)
        sub_data = await fetch_sources(client, {**mega, "type": "sub"})
        sub_file = _file_of(sub_data) if sub_data else None
        if file_url and sub_file and file_url == sub_file:
            print(f"Megaplay: {mega['api_host']}/{mega['id']} dub == sub file -> no real dub")
            return None

    return data


async def check_playable(client: httpx.AsyncClient, file_url: str, referer: str) -> bool:
    """True when the CDN actually serves the manifest for this referer.

    vidwish.live hands out master.m3u8 URLs that its CDN then 403s, so a
    resolved URL is not on its own evidence of a playable stream.
    """
    try:
        resp = await client.get(file_url, headers={"User-Agent": UA, "Referer": referer})
    except Exception:
        return False
    return resp.status_code == 200 and "#EXTM3U" in resp.text


def build_result(data: Dict[str, Any], mega: Dict[str, str], server_name: str) -> Dict[str, Any]:
    """Turn a getSources payload into the provider {streams, subtitles} shape."""
    sources = data.get("sources") or {}
    file_url = sources.get("file") if isinstance(sources, dict) else None
    if not file_url:
        return {"streams": [], "subtitles": []}

    referer = f"https://{mega['api_host']}/"

    subtitles = []
    for track in data.get("tracks") or []:
        if not isinstance(track, dict) or not track.get("file"):
            continue
        if (track.get("kind") or "").lower() == "thumbnails":
            continue
        label = re.split(r'\s*\(-\s*', track.get("label", "") or "")[0].strip()
        subtitles.append({
            "url": track["file"],
            "lang": label or "English",
            "kind": "captions",
            "referer": referer,
        })

    return {
        "intro": _skip_marker(data.get("intro")),
        "outro": _skip_marker(data.get("outro")),
        "streams": [{
            "quality": "auto",
            "url": file_url,
            "server": server_name,
            "category": mega["type"],
            "referer": referer,
        }],
        "subtitles": subtitles,
    }


def _skip_marker(marker):
    """A skip range, or None when the site has no data for this episode.

    Megaplay reports "no markers" as {"start": 0, "end": 0}. Passed through
    as-is, the player's `t >= start && t <= end` test matches at t=0 and flashes
    the button at the start of every episode that has no intro.
    """
    if not isinstance(marker, dict):
        return None
    start = marker.get("start") or 0
    end = marker.get("end") or 0
    if end <= start:
        return None
    return {"start": start, "end": end}
