"""ZokoAnime: streams looked up by MyAnimeList ID and episode number.

This is the player behind hianime.at (the source ani-cli switched to). Its
embed is addressed as /stream/mal/<mal id>/<episode>/<sub|dub>, so there is no
title search and no guessing: the AniList entry's MAL ID names the show
exactly, and MAL splits seasons the same way AniList does, so episode N is
episode N. That removes the whole "Mapping failed" class of misses the
title-searching providers suffer from, and its catalogue carries dubs for far
more shows than the others.

The embed page ships its player config as `window.__P`: base64 of the JSON
XORed with the key "otaku-embed-v1".
"""

import base64
import json
import re
from typing import Any, Dict, List, Optional

import httpx

from .base import BaseProvider
from ..services import anilist_media

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

EMBED_URL = "https://zokoanime.video/stream/mal/{mal}/{episode}/{category}"
# The embed is served to its parent site; the stream CDN wants the embed host.
EMBED_REFERER = "https://hianime.at/"
STREAM_REFERER = "https://zokoanime.video/"

_BLOB_RE = re.compile(r'window\.__P="([^"]+)"')
_KEY = b"otaku-embed-v1"


def decode_blob(blob: str) -> Optional[Dict[str, Any]]:
    """The player config inside an embed page, or None if it is not one."""
    try:
        raw = base64.b64decode(blob)
        text = bytes(b ^ _KEY[i % len(_KEY)] for i, b in enumerate(raw)).decode("utf-8")
        data = json.loads(text)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def _skip(marker: Any) -> Optional[Dict[str, int]]:
    """A {start, end} skip range in seconds, or None when there is none."""
    if not isinstance(marker, dict):
        return None
    try:
        start, end = int(marker.get("start") or 0), int(marker.get("end") or 0)
    except (TypeError, ValueError):
        return None
    return {"start": start, "end": end} if end > start else None


class ZokoAnimeProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "ZokoAnime"

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=20.0, follow_redirects=True,
                                     headers={"User-Agent": UA}) as client:
            try:
                mal_id = await self.map_anime(client, anilist_id)
                if not mal_id:
                    return {"error": "No MyAnimeList ID for this anime"}

                data = await self._player(client, mal_id, episode, category)
                if not data or not data.get("src"):
                    return {"error": f"ZokoAnime has no {category} for episode {episode}"}

                if category == "dub":
                    # A title with no dub can still answer the /dub address with
                    # the subbed video; serving that as a dub is exactly what the
                    # player's Audio menu must never do.
                    sub = await self._player(client, mal_id, episode, "sub")
                    if sub and sub.get("src") == data.get("src"):
                        return {"error": "ZokoAnime's dub is the sub video (no real dub)"}

                if not await self._playable(client, data["src"]):
                    return {"error": "ZokoAnime stream did not answer"}

                return self._result(data, category)
            except Exception as e:  # noqa: BLE001 - a provider reports, it does not raise
                return {"error": f"ZokoAnime failed: {type(e).__name__}: {e}"}

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str) -> Optional[int]:
        """The AniList entry's MyAnimeList ID -- the only mapping this needs."""
        info = await anilist_media.get_media(client, anilist_id)
        mal = info.get("mal_id")
        try:
            return int(mal) if mal else None
        except (TypeError, ValueError):
            return None

    async def _player(self, client: httpx.AsyncClient, mal_id: int, episode: int,
                      category: str) -> Optional[Dict[str, Any]]:
        url = EMBED_URL.format(mal=mal_id, episode=episode, category=category)
        resp = await client.get(url, headers={"Referer": EMBED_REFERER})
        if resp.status_code != 200:
            return None
        # A missing episode or show answers 200 with an empty player, not a
        # 404, so the absence of the config blob is the "not found" signal.
        m = _BLOB_RE.search(resp.text)
        return decode_blob(m.group(1)) if m else None

    async def _playable(self, client: httpx.AsyncClient, src: str) -> bool:
        try:
            resp = await client.get(src, headers={"Referer": STREAM_REFERER})
        except httpx.HTTPError:
            return False
        return resp.status_code == 200 and "#EXTM3U" in resp.text

    def _result(self, data: Dict[str, Any], category: str) -> Dict[str, Any]:
        subtitles = []
        for track in data.get("subtitles") or []:
            if not isinstance(track, dict) or not track.get("src"):
                continue
            subtitles.append({
                "url": track["src"],
                # "lang" is "en" on every track; the label is the real language.
                "lang": track.get("label") or "English",
                "kind": "captions",
                "default": bool(track.get("default")),
                "referer": STREAM_REFERER,
            })
        skip = data.get("skip") if isinstance(data.get("skip"), dict) else {}
        return {
            "streams": [{
                "quality": "auto",
                "url": data["src"],
                "server": "ZokoAnime",
                "category": category,
                "referer": STREAM_REFERER,
            }],
            "subtitles": subtitles,
            "intro": _skip(skip.get("intro")),
            "outro": _skip(skip.get("outro")),
        }

    # BaseProvider's step-by-step hooks. This source needs no episode or server
    # lookup -- the MAL-keyed address is the episode -- so they are trivial.
    async def get_episode(self, anime_id: str, episode_num: int) -> str:
        return str(episode_num)

    async def get_servers(self, episode_id: str) -> List[Dict[str, str]]:
        return []

    async def extract(self, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        return {"streams": [], "subtitles": []}
