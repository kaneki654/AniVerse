import asyncio
import httpx

async def run():
    url = "https://hianime-api.vercel.app/api/v2/hianime/anime/tying-the-knot-with-an-amagami-sister-19307/episodes"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(url)
            print("hianime-api.vercel.app:", r.status_code)
            if r.status_code == 200:
                print(r.json())
        except: pass
        
    url = "https://aniwatch-api-net.vercel.app/api/v2/hianime/anime/tying-the-knot-with-an-amagami-sister-19307/episodes"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(url)
            print("aniwatch-api-net:", r.status_code)
            if r.status_code == 200:
                print(r.text[:200])
        except: pass
        
    url = "https://c-api.vercel.app/api/v2/hianime/anime/tying-the-knot-with-an-amagami-sister-19307/episodes"
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            r = await client.get(url)
            print("c-api:", r.status_code)
            if r.status_code == 200:
                print(r.text[:200])
        except: pass

asyncio.run(run())
