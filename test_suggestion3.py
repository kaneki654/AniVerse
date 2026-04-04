import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        # What does httpx do when we pass quoted string?
        resp = await client.get("http://localhost:8001/anime/search/demon%20slayer")
        data = resp.json()
        print("Data length:", len(data))
        for item in data[:5]:
            try:
                name = item["title"].get("english") or item["title"].get("romaji")
                poster = item["coverImage"]["large"]
            except Exception as e:
                print("Error on item:", item)
                print(e)
                
asyncio.run(run())
