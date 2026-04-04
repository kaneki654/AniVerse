import asyncio
import httpx
import json

async def run():
    query = """
    query ($search: String, $genres: [String], $page: Int, $sort: [MediaSort]) {
      Page (page: $page, perPage: 24) {
        pageInfo {
          total
          currentPage
          lastPage
          hasNextPage
          perPage
        }
        media (type: ANIME, search: $search, genre_in: $genres, sort: $sort) {
          id
          title { romaji english }
          coverImage { large }
        }
      }
    }
    """
    
    # Test 1: Just search
    variables = {"search": "Naruto", "page": 1, "sort": ["SEARCH_MATCH", "POPULARITY_DESC"]}
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
        print("Search only:", len(resp.json().get("data", {}).get("Page", {}).get("media", [])))
        
        # Test 2: Search + genres
        variables = {"search": "Naruto", "genres": ["Action"], "page": 1, "sort": ["SEARCH_MATCH", "POPULARITY_DESC"]}
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
        print("Search + Genre:", len(resp.json().get("data", {}).get("Page", {}).get("media", [])))

        # Test 3: Genres only
        variables = {"genres": ["Action", "Fantasy"], "page": 1, "sort": ["TRENDING_DESC"]}
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
        print("Genres only:", len(resp.json().get("data", {}).get("Page", {}).get("media", [])))

        # Test 4: Nothing (Browse)
        variables = {"page": 1, "sort": ["TRENDING_DESC"]}
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
        print("Browse:", len(resp.json().get("data", {}).get("Page", {}).get("media", [])))
        
        print("Page Info:", resp.json()["data"]["Page"]["pageInfo"])

asyncio.run(run())
