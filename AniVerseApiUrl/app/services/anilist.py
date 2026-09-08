import asyncio
import httpx
from typing import Optional, Dict, Any, List

from app.core.cache import cache
from app.services import anime_meta

class AniListService:
    """Metadata for the API routes.

    A thin facade over anime_meta, which prefers AniList and falls back to
    Kitsu when it is unavailable -- as it is right now, answering every query
    with 403 "temporarily disabled due to severe stability issues". Every
    method used to query AniList directly, so that outage emptied the home
    screen, search and every genre at once.
    """

    API_URL = "https://graphql.anilist.co"

    # AniList currently advertises a degraded budget (x-ratelimit-limit of 30/min
    # rather than the documented 90), and opening a genre screen fires one query
    # per tap. The old code posted the request, ignored the status code entirely
    # and returned None for anything that was not a clean 200 -- so a 429 came
    # back as an empty list and every genre screen said "nothing found" until the
    # window rolled over. Retry the throttled ones instead.
    _MAX_ATTEMPTS = 3

    @classmethod
    async def _execute_query(cls, query: str, variables: Dict[str, Any] = None) -> Optional[Dict[str, Any]]:
        payload = {"query": query, "variables": variables or {}}
        async with httpx.AsyncClient(timeout=20) as client:
            for attempt in range(cls._MAX_ATTEMPTS):
                try:
                    response = await client.post(cls.API_URL, json=payload)
                except Exception as e:
                    print(f"AniList API error: {e}")
                    return None

                if response.status_code == 429:
                    if attempt == cls._MAX_ATTEMPTS - 1:
                        print("AniList rate limited; giving up after "
                              f"{cls._MAX_ATTEMPTS} attempts")
                        return None
                    # Retry-After is in seconds and is usually the remainder of
                    # the current minute; cap it so one throttled call cannot
                    # stall a request behind it for a whole minute.
                    try:
                        wait = float(response.headers.get("retry-after", 2))
                    except ValueError:
                        wait = 2.0
                    wait = min(max(wait, 1.0), 8.0)
                    print(f"AniList rate limited; retrying in {wait:.0f}s")
                    await asyncio.sleep(wait)
                    continue

                if response.status_code != 200:
                    print(f"AniList HTTP {response.status_code}")
                    return None

                try:
                    data = response.json()
                except Exception as e:
                    print(f"AniList returned non-JSON: {e}")
                    return None

                if data.get("errors"):
                    print(f"AniList GraphQL errors: {data['errors']}")
                if "data" in data and data["data"] is not None:
                    return data["data"]
                return None
        return None

    @classmethod
    async def search_anime(cls, query: str) -> List[Dict[str, Any]]:
        result = await anime_meta.search_media(query=query, page=1, per_page=20)
        return result.get("media", []) if isinstance(result, dict) else (result or [])

    @classmethod
    async def get_popular(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        return await anime_meta.fetch_popular(page, per_page)

    @classmethod
    async def get_trending(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        return await anime_meta.fetch_trending(page, per_page)

    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        return await anime_meta.fetch_latest(page, per_page)

    @classmethod
    async def get_upcoming(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        return await anime_meta.fetch_upcoming(page, per_page)

    @classmethod
    async def search_by_genre(cls, genre: str, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        # Cache hits are what keep the genre screens usable: AniList allows about
        # 30 queries a minute and browsing fires one per tap plus one per scroll
        # page. Only successful, non-empty pages are stored -- caching an empty
        # would pin "nothing found" in place for the whole TTL.
        key = f"anilist:genre:{genre}:{page}:{per_page}"
        cached = cache.get(key)
        if cached is not None:
            return cached

        media = await anime_meta.fetch_by_genre(genre, page, per_page)
        if media:
            cache.set(key, media, ttl_seconds=1800)
        return media or []

    @classmethod
    async def browse(cls, sort: str = "POPULARITY_DESC", page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        return await anime_meta.browse_media(sort, page, per_page)


anilist_service = AniListService()
