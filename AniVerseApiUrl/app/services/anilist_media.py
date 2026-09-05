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
    resp = await client.post("https://graphql.anilist.co", json={
        "query": MEDIA_QUERY,
        "variables": {"id": int(anilist_id)},
    })
    if resp.status_code != 200:
        # A 429 here must not be cached as "this show has no title", or the
        # empty result would poison mapping for the whole TTL.
        raise RuntimeError(f"AniList HTTP {resp.status_code}")
    info = _shape((resp.json().get("data") or {}).get("Media"))
    if not info["title_ro"] and not info["title_en"]:
        raise RuntimeError("AniList returned no titles")
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

    resp = await client.post("https://graphql.anilist.co", json={
        "query": FULL_MEDIA_QUERY,
        "variables": {"id": int(anilist_id)},
    }, timeout=15)
    # AniList answers an unknown id with 404; that is "no such anime", not a
    # lookup failure, and must not surface as a 502.
    if resp.status_code == 404:
        return None
    if resp.status_code != 200:
        raise RuntimeError(f"AniList HTTP {resp.status_code}")

    media = (resp.json().get("data") or {}).get("Media")
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
