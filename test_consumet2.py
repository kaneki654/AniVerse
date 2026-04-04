import asyncio
import httpx

async def run():
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Search jujutsu kaisen on zoro
        r = await client.get("https://api.consumet.org/anime/zoro/info?id=jujutsu-kaisen-534")
        print("Info:", r.status_code, r.text[:200])

asyncio.run(run())
