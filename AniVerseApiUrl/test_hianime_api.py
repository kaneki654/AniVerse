import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        print("Testing hianime-api...")
        try:
            resp = await client.get("https://hianime-api.vercel.app/anime/search?q=jujutsu kaisen")
            if resp.status_code == 200:
                data = resp.json()
                animes = data.get("animes", [])
                if animes:
                    anime_id = animes[0]["id"]
                    print(f"Found Anime ID: {anime_id}")
                    
                    # Get episodes
                    resp2 = await client.get(f"https://hianime-api.vercel.app/anime/episodes/{anime_id}")
                    ep_data = resp2.json()
                    episodes = ep_data.get("episodes", [])
                    if episodes:
                        ep_id = episodes[0]["episodeId"]
                        print(f"Found Episode ID: {ep_id}")
                        
                        # Get servers
                        resp3 = await client.get(f"https://hianime-api.vercel.app/anime/servers?episodeId={ep_id}")
                        servers_data = resp3.json()
                        print(f"Servers: {servers_data.keys() if isinstance(servers_data, dict) else servers_data}")
                        
                        # Get streams
                        resp4 = await client.get(f"https://hianime-api.vercel.app/anime/episode-srcs?id={ep_id}&server=vidstreaming&category=sub")
                        stream_data = resp4.json()
                        sources = stream_data.get("sources", [])
                        print("Streams found:", [s.get('url') for s in sources])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
