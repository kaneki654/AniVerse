import httpx
import asyncio
import json

async def run():
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://api.ani.zip/mappings?anilist_id=16498")
        data = resp.json()
        print(json.dumps(data.get("mappings", {}), indent=2))

asyncio.run(run())
