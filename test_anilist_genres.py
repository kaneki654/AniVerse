import asyncio
import httpx
import json

async def run():
    query = '''
    query ($search: String, $genres: [String], $page: Int, $sort: [MediaSort]) {
      Page (page: $page, perPage: 24) {
        media (type: ANIME, search: $search, genre_in: $genres, sort: $sort) {
          id
          title { romaji english }
        }
      }
    }
    '''
    variables = {
        "page": 1,
        "genres": ["Action"],
        "sort": ["TRENDING_DESC"]
    }
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
        print(json.dumps(resp.json(), indent=2))

asyncio.run(run())
