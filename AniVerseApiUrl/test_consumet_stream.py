import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            # Step 1: Search for Jujutsu Kaisen on Gogoanime via Consumet
            resp = await client.get("https://consumet-api-clone.vercel.app/anime/gogoanime/jujutsu-kaisen-tv")
            print("Info Status:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                print("Title:", data.get('title'))
                
                # Step 2: Get episode ID
                episodes = data.get('episodes', [])
                if episodes:
                    ep_id = episodes[0]['id']
                    print("Episode ID:", ep_id)
                    
                    # Step 3: Get stream sources
                    resp2 = await client.get(f"https://consumet-api-clone.vercel.app/anime/gogoanime/watch/{ep_id}")
                    print("Watch Status:", resp2.status_code)
                    if resp2.status_code == 200:
                        watch_data = resp2.json()
                        sources = watch_data.get('sources', [])
                        print("Found Streams:", len(sources))
                        if sources:
                            print("Sample Stream:", sources[0]['url'])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
