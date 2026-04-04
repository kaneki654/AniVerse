import os

new_methods = """
    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
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
"""

file_path = "AniVerseApiUrl/app/services/anilist.py"
with open(file_path, "r") as f:
    content = f.read()

if "get_recently_updated" not in content:
    content = content.replace("anilist_service = AniListService()", new_methods + "\nanilist_service = AniListService()\n")
    with open(file_path, "w") as f:
        f.write(content)
    print("Added new methods to anilist.py")
else:
    print("Methods already exist in anilist.py")
