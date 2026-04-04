import asyncio
import httpx
import json

async def run():
    query = '''
    query {
      GenreCollection
    }
    '''
    async with httpx.AsyncClient() as client:
        resp = await client.post("https://graphql.anilist.co", json={"query": query})
        print(json.dumps(resp.json(), indent=2))

asyncio.run(run())
