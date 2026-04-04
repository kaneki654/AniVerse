import asyncio
import httpx

async def run():
    query = '''
    query {
      Page(page: 1, perPage: 1) {
        media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) {
          id
          title { english romaji }
        }
      }
    }
    '''
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query})
        media = resp.json()["data"]["Page"]["media"][0]
        print(f"ID: {media['id']}, Title: {media['title']['english'] or media['title']['romaji']}")

asyncio.run(run())
