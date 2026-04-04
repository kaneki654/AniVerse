import asyncio
import httpx

async def test():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            resp = await client.get("https://api.consumet.org/meta/anilist/info/101280", timeout=10)
            print("Status:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                print("Title:", data.get('title'))
                episodes = data.get('episodes', [])
                if episodes:
                    print("First Ep ID:", episodes[0].get('id'))
                    ep_id = episodes[0].get('id')
                    resp2 = await client.get(f"https://api.consumet.org/meta/anilist/watch/{ep_id}", timeout=10)
                    print("Watch Status:", resp2.status_code)
                    if resp2.status_code == 200:
                        watch_data = resp2.json()
                        print("Sources:", [s.get('url') for s in watch_data.get('sources', [])])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
