import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get("https://hianime-api.vercel.app/api/v2/hianime/search?q=jujutsu kaisen")
            print("Search status:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                animes = data.get("data", {}).get("animes", [])
                if animes:
                    anime_id = animes[0]["id"]
                    print(f"Found Anime ID: {anime_id}")
                    
                    resp2 = await client.get(f"https://hianime-api.vercel.app/api/v2/hianime/anime/{anime_id}/episodes")
                    print("Eps status:", resp2.status_code)
                    episodes = resp2.json().get("data", {}).get("episodes", [])
                    if episodes:
                        ep_id = episodes[0]["episodeId"]
                        print(f"Found Episode ID: {ep_id}")
                        
                        resp3 = await client.get(f"https://hianime-api.vercel.app/api/v2/hianime/episode/servers?animeEpisodeId={ep_id}")
                        print("Servers status:", resp3.status_code)
                        print("Servers:", [s["serverName"] for s in resp3.json().get("data", {}).get("sub", [])])
                        
                        resp4 = await client.get(f"https://hianime-api.vercel.app/api/v2/hianime/episode/sources?animeEpisodeId={ep_id}&server=hd-1&category=sub")
                        print("Sources status:", resp4.status_code)
                        sources = resp4.json().get("data", {}).get("sources", [])
                        print("Streams:", [s["url"] for s in sources])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
