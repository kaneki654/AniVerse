import asyncio
import httpx

async def test():
    urls = [
        "https://hianime-api.vercel.app",
        "https://aniwatch-api-net.vercel.app",
        "https://anime-api.hisoka17.vercel.app/anime/gogoanime/naruto",
        "https://api.consumet.org/anime/gogoanime/info/naruto",
        "https://consumet-api.herokuapp.com/",
        "https://c-api.vercel.app/"
    ]
    async with httpx.AsyncClient(timeout=5) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code}")
            except Exception as e:
                print(f"{url}: {e}")

asyncio.run(test())
