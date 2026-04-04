import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get("https://c-api.vercel.app/anime/gogoanime/info/jujutsu-kaisen-tv")
            print("Info:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                print("Title:", data.get('title'))
                
                episodes = data.get('episodes', [])
                if episodes:
                    ep_id = episodes[0]['id']
                    print("Episode ID:", ep_id)
                    
                    resp2 = await client.get(f"https://c-api.vercel.app/anime/gogoanime/watch/{ep_id}")
                    print("Watch Status:", resp2.status_code)
                    if resp2.status_code == 200:
                        watch_data = resp2.json()
                        sources = watch_data.get("sources", [])
                        print("Streams:", [s.get('url') for s in sources])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
