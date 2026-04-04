import asyncio
import httpx

async def run():
    async with httpx.AsyncClient(timeout=15.0) as client:
        # Search jujutsu kaisen on gogoanime
        r1 = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/jujutsu-kaisen-tv")
        print("Search:", r1.status_code)
        
        # Get episodes
        r2 = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/info/jujutsu-kaisen-tv")
        print("Info:", r2.status_code)
        
        # Get stream
        r3 = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/watch/jujutsu-kaisen-tv-episode-1")
        print("Stream:", r3.status_code)
        if r3.status_code == 200:
            print("Sources:", r3.json().get("sources", []))

asyncio.run(run())
