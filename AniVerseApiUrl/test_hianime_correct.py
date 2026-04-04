import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get("https://hianime-api.vercel.app/anime/search?q=jujutsu")
            data = resp.json()
            animes = data.get("animes", [])
            print("Found animes:", len(animes))
            if animes:
                anime_id = animes[0]["id"]
                print("Anime ID:", anime_id)
                
                resp2 = await client.get(f"https://hianime-api.vercel.app/anime/episodes/{anime_id}")
                episodes = resp2.json().get("episodes", [])
                print("Found episodes:", len(episodes))
                if episodes:
                    ep_id = episodes[0]["episodeId"]
                    print("Ep ID:", ep_id)
                    
                    resp3 = await client.get(f"https://hianime-api.vercel.app/anime/servers?episodeId={ep_id}")
                    print("Servers:", resp3.json())
                    
                    resp4 = await client.get(f"https://hianime-api.vercel.app/anime/episode-srcs?id={ep_id}&server=vidstreaming&category=sub")
                    print("Sources status:", resp4.status_code)
                    if resp4.status_code == 200:
                        sources = resp4.json().get("sources", [])
                        print("Sources:", [s["url"] for s in sources])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
