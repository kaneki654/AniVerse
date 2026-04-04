import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://api.ani.zip/mappings?anilist_id=16498")
        if r.status_code == 200:
            print(r.json())
        else:
            print("Failed", r.status_code)
asyncio.run(run())
