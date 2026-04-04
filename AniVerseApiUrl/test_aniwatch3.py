import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        # Get eps
        resp = await client.get("https://hianime-api.vercel.app/anime/episodes/jujutsu-kaisen-tv-534")
        print("Eps:", resp.status_code)
        if resp.status_code == 200:
            episodes = resp.json().get("episodes", [])
            print("Num eps:", len(episodes))
            ep_id = episodes[0]["episodeId"]
            print("First Ep ID:", ep_id)
            
            # Get servers
            resp2 = await client.get(f"https://hianime-api.vercel.app/anime/servers?episodeId={ep_id}")
            print("Servers:", resp2.status_code)
            if resp2.status_code == 200:
                print(resp2.json())
                
            # Get sources
            resp3 = await client.get(f"https://hianime-api.vercel.app/anime/episode-srcs?id={ep_id}&server=vidstreaming&category=sub")
            print("Sources:", resp3.status_code)
            if resp3.status_code == 200:
                print(resp3.json().get("sources"))

asyncio.run(test())
