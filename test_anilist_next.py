import asyncio
import httpx

async def run():
    query = '''
    query ($page: Int, $perPage: Int) {
      Page (page: $page, perPage: $perPage) {
        media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
          id
          title { romaji english }
          coverImage { large }
          episodes
          nextAiringEpisode { episode }
        }
      }
    }
    '''
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"page": 1, "perPage": 5}})
        print(resp.json())

asyncio.run(run())
