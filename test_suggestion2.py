import asyncio
import httpx
from urllib.parse import quote

async def run():
    async with httpx.AsyncClient() as client:
        q = "demon slayer"
        resp = await client.get(f"http://localhost:8001/anime/search/{quote(q)}")
        data = resp.json()
        
        for item in data[:5]:
            try:
                name = item["title"].get("english") or item["title"].get("romaji")
                poster = item["coverImage"]["large"]
            except Exception as e:
                print("Error on item:", item)
                print(e)

asyncio.run(run())
