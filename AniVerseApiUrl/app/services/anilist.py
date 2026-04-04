import httpx
from typing import Optional, Dict, Any, List

class AniListService:
    API_URL = "https://graphql.anilist.co"

    @classmethod
    async def _execute_query(cls, query: str, variables: Dict[str, Any] = None) -> Optional[Dict[str, Any]]:
        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    cls.API_URL, 
                    json={"query": query, "variables": variables or {}}
                )
                data = response.json()
                if "data" in data:
                    return data["data"]
            except Exception as e:
                print(f"AniList API error: {e}")
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
              episodes
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
              episodes
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"genre": genre, "page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
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
              episodes
            }
          }
        }
        '''
        data = await cls._execute_query(graphql_query, {"sort": [sort], "page": page, "perPage": per_page})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []

anilist_service = AniListService()

