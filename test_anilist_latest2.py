import asyncio
import httpx

async def run():
    query = '''
    query ($page: Int, $perPage: Int) {
      Page (page: $page, perPage: $perPage) {
        media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
          id
          title { romaji english }
          episodes
          nextAiringEpisode { episode }
          airingSchedule(notYetAired: false) {
            edges { node { episode } }
          }
        }
      }
    }
    '''
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"page": 1, "perPage": 10}})
        import json
        print(json.dumps(resp.json(), indent=2))

asyncio.run(run())
