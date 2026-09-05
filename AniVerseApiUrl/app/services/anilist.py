import asyncio
import httpx
from typing import Optional, Dict, Any, List

from app.core.cache import cache

class AniListService:
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
        graphql_query = """
        query ($search: String, $page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        """
        data = await cls._execute_query(graphql_query, {"search": query, "page": 1, "perPage": 20})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []

    @classmethod
    async def get_popular(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = """
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: POPULARITY_DESC) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        """
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []

    @classmethod
    async def get_trending(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = """
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: TRENDING_DESC) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        """
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []


    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        import time
        current_time = int(time.time())
        graphql_query = '''
        query ($page: Int, $perPage: Int, $time: Int) {
          Page (page: $page, perPage: $perPage) {
            airingSchedules (
              airingAt_lesser: $time,
              sort: TIME_DESC
            ) {
              episode
              media {
                id
                title { romaji english }
                coverImage { large }
                episodes
              }
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page, "time": current_time})
        if data and "Page" in data and "airingSchedules" in data["Page"]:
            # Remap to look like the normal media objects but with the explicit exact episode number
            results = []
            seen_ids = set()
            for schedule in data["Page"]["airingSchedules"]:
                media = schedule.get("media")
                if not media: continue
                if media["id"] in seen_ids: continue
                seen_ids.add(media["id"])
                
                # Attach the exact aired episode number
                media["exact_latest_episode"] = schedule.get("episode")
                results.append(media)
            return results
        return []

    @classmethod
    async def get_upcoming(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []

    @classmethod
    async def search_by_genre(cls, genre: str, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($genre: String, $page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, genre: $genre, sort: POPULARITY_DESC) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        '''
        # Cache hits are what actually keep the genre screens working: AniList
        # allows ~30 queries a minute and browsing genres fires one per tap plus
        # one per infinite-scroll page, which exhausted the budget in seconds.
        # Only successful, non-empty pages are stored -- caching a throttled
        # empty would pin "nothing found" in place for the whole TTL.
        key = f"anilist:genre:{genre}:{page}:{per_page}"
        cached = cache.get(key)
        if cached is not None:
            return cached

        variables = {"genre": genre, "page": page, "perPage": per_page}
        for attempt in range(2):
            data = await cls._execute_query(graphql_query, variables)
            media = ((data or {}).get("Page") or {}).get("media")
            if media:
                cache.set(key, media, ttl_seconds=1800)
                return media
            # AniList intermittently answers 200 with an empty page under load.
            # Page 1 of a stock genre is never genuinely empty, so treat that as
            # the hiccup it is and try once more; deeper pages really can run
            # past the end, so those are returned as-is.
            if page != 1 or attempt == 1:
                break
            print(f"AniList returned an empty page 1 for genre {genre!r}; retrying")
            await asyncio.sleep(1.0)
        return []

    @classmethod
    async def browse(cls, sort: str = "POPULARITY_DESC", page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($sort: [MediaSort], $page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: $sort) {
              id
              title { romaji english }
              coverImage { large }
              status
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"sort": [sort], "page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []

anilist_service = AniListService()

