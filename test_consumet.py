import asyncio
import httpx

async def run():
    async with httpx.AsyncClient(timeout=15.0) as client:
        # Search jujutsu kaisen on zoro
        r = await client.get("https://api.consumet.org/anime/zoro/info?id=jujutsu-kaisen-534")
        print("Info:", r.status_code)
        
        # Get stream
        r2 = await client.get("https://api.consumet.org/anime/zoro/watch?episodeId=jujutsu-kaisen-534$episode$10168")
        print("Stream:", r2.status_code)

asyncio.run(run())
