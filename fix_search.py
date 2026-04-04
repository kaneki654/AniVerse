import os

# 1. Update Anilist service
anilist_path = 'AniVerseApiUrl/app/services/anilist.py'
with open(anilist_path, 'r') as f:
    anilist_content = f.read()

old_search = """    @classmethod
    async def search_anime(cls, query: str) -> Optional[Dict[str, Any]]:
        graphql_query = \"\"\"
        query ($search: String) {
          Media (search: $search, type: ANIME, sort: SEARCH_MATCH) {
            id
            title { romaji english }
            coverImage { large }
          }
        }
        \"\"\"
        data = await cls._execute_query(graphql_query, {"search": query})
        if data and "Media" in data and data["Media"]:
            return data["Media"]
        return None"""

new_search = """    @classmethod
    async def search_anime(cls, query: str) -> List[Dict[str, Any]]:
        graphql_query = \"\"\"
        query ($search: String, $page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id
              title { romaji english }
              coverImage { large }
            }
          }
        }
        \"\"\"
        data = await cls._execute_query(graphql_query, {"search": query, "page": 1, "perPage": 20})
        if data and "Page" in data and "media" in data["Page"]:
            return data["Page"]["media"]
        return []"""

if old_search in anilist_content:
    anilist_content = anilist_content.replace(old_search, new_search)
    with open(anilist_path, 'w') as f:
        f.write(anilist_content)
    print("Updated search_anime in anilist.py")
else:
    print("Could not find search_anime in anilist.py")

# 2. Update router.py
router_path = 'AniVerseApiUrl/app/api/router.py'
with open(router_path, 'r') as f:
    router_content = f.read()

old_router_resolve = """    anime_info = await anilist_service.search_anime(query)
    if not anime_info:
        raise HTTPException(status_code=404, detail="Anime not found on AniList")
        
    anilist_id = str(anime_info["id"])"""

new_router_resolve = """    anime_list = await anilist_service.search_anime(query)
    if not anime_list:
        raise HTTPException(status_code=404, detail="Anime not found on AniList")
        
    anime_info = anime_list[0]
    anilist_id = str(anime_info["id"])"""

if old_router_resolve in router_content:
    router_content = router_content.replace(old_router_resolve, new_router_resolve)
    with open(router_path, 'w') as f:
        f.write(router_content)
    print("Updated router.py")
else:
    print("Could not find resolve_by_name in router.py")

