"""Shared AniList media lookup for providers.

Every provider needs the same title/episode/format facts for the same AniList
id, and the orchestrator runs four of them across two categories - eight
identical GraphQL queries per resolve, which is enough to trip AniList's rate
limit and make mapping fail intermittently.

This module answers from cache and collapses concurrent misses for the same id
onto a single in-flight request.
"""

import asyncio
from typing import Any, Dict, Optional

import httpx

from app.core.cache import cache
from app.services import anime_meta

MEDIA_QUERY = """
query ($id: Int) {
  Media (id: $id, type: ANIME) {
    title { romaji english }
    episodes
    duration
    format
  }
}
"""

_TTL_SECONDS = 6 * 60 * 60
_inflight: Dict[str, asyncio.Future] = {}
_lock = asyncio.Lock()


def _cache_key(anilist_id: str) -> str:
    return f"anilist:media:{anilist_id}"


def _shape(media: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    media = media or {}
    title = media.get("title") or {}
    return {
        "title_ro": title.get("romaji") or "",
        "title_en": title.get("english") or "",
        "episodes": media.get("episodes"),
        "duration": media.get("duration") or 24,
        "format": media.get("format") or "TV",
    }


async def _query(client: httpx.AsyncClient, anilist_id: str) -> Dict[str, Any]:
    """Titles and episode facts for an id, used to find the show on providers.

    Goes through anime_meta so this survives an AniList outage. Querying AniList
    directly meant a 403 here failed every provider's title lookup at once --
    "Anime not found on GogoAnime (Mapping failed)" for everything, so nothing
    played even though the metadata pages themselves had already fallen back.

    A failure still raises rather than returning empty titles: caching "this
    show has no name" would poison provider mapping for the whole TTL.
    """
    media = await anime_meta.fetch_media(anilist_id, client)
    if not media:
        raise RuntimeError(f"no metadata for AniList id {anilist_id}")
    info = _shape(media)
    if not info["title_ro"] and not info["title_en"]:
        raise RuntimeError("no titles for AniList id %s" % anilist_id)
    return info


FULL_MEDIA_QUERY = """
query ($id: Int) {
  Media (id: $id, type: ANIME) {
    id
    title { romaji english }
    description
    coverImage { large }
    bannerImage
    episodes
    duration
    genres
    averageScore
    status
    format
  }
}
"""


async def get_full_media(client: httpx.AsyncClient, anilist_id: str) -> Optional[Dict[str, Any]]:
    """Full AniList Media record for a detail page, cached.

    Returned in AniList's own shape (title/coverImage/genres/...) because that is
    what the clients already parse; get_media() above is a trimmed set used for
    provider mapping and is not enough to render a detail screen.
    """
    key = f"anilist:full:{anilist_id}"
    cached = cache.get(key)
    if cached:
        return cached

    # Through anime_meta so a detail page still renders when AniList is down:
    # it prefers AniList and falls back to Kitsu, re-keyed onto the same AniList
    # id so episode resolution and saved history keep working. Querying AniList
    # directly here meant every detail page 502'd for the whole outage.
    media = await anime_meta.fetch_media(anilist_id, client)
    if not media:
        return None

    cache.set(key, media, ttl_seconds=_TTL_SECONDS)
    return media


async def get_media(client: httpx.AsyncClient, anilist_id: str) -> Dict[str, Any]:
    """Cached AniList facts for an id. Raises if the lookup genuinely fails."""
    key = _cache_key(anilist_id)
    cached = cache.get(key)
    if cached:
        return cached

    async with _lock:
        pending = _inflight.get(key)
        if pending is None:
            pending = asyncio.get_running_loop().create_future()
            _inflight[key] = pending
            owner = True
        else:
            owner = False

    if not owner:
        return await asyncio.shield(pending)

    try:
        info = await _query(client, anilist_id)
    except Exception as e:
        async with _lock:
            _inflight.pop(key, None)
        if not pending.done():
            pending.set_exception(e)
        # Surface the failure to every waiter, but don't leave it unretrieved.
        pending.exception()
        raise

    cache.set(key, info, ttl_seconds=_TTL_SECONDS)
    async with _lock:
        _inflight.pop(key, None)
    if not pending.done():
        pending.set_result(info)
    return info
