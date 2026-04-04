import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/info/jujutsu-kaisen-tv")
            print("Info:", resp.status_code)
            
            resp2 = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/watch/jujutsu-kaisen-tv-episode-1")
            print("Watch:", resp2.status_code)
            if resp2.status_code == 200:
                data = resp2.json()
                print("Sources:", [s.get("url") for s in data.get("sources", [])])
        except Exception as e:
            print(e)

asyncio.run(test())
