import asyncio
import httpx

async def test():
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        resp = await client.get("https://animepahe.ru/api?m=search&q=jujutsu+kaisen")
        print("Search:", resp.status_code)
        if resp.status_code == 200:
            data = resp.json()
            if data.get("data"):
                session = data["data"][0]["session"]
                print("Session:", session)
                
                resp2 = await client.get(f"https://animepahe.ru/api?m=release&id={session}&sort=episode_asc&page=1")
                print("Episodes:", resp2.status_code)
                ep_data = resp2.json()
                if ep_data.get("data"):
                    ep_session = ep_data["data"][0]["session"]
                    print("Ep Session:", ep_session)
                    
                    resp3 = await client.get(f"https://animepahe.ru/api?m=links&id={session}&p=kwijk") # Actually need proper link format
                    # Need to check the episode page
                    resp_page = await client.get(f"https://animepahe.ru/play/{session}/{ep_session}")
                    print("Play page:", resp_page.status_code)
                    print("Play HTML:", resp_page.text[:200])

asyncio.run(test())
