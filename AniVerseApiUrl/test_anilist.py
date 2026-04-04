import asyncio
import httpx

async def run():
    query = """
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        idMal
        title { romaji english }
      }
    }
    """
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"id": 16498}})
        print(resp.json())

asyncio.run(run())
