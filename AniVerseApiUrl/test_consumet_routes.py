import asyncio
import httpx

async def test():
    urls = [
        "https://consumet-api-clone.vercel.app/meta/anilist/info/101280",
        "https://consumet-api-clone.vercel.app/anime/gogoanime/jujutsu-kaisen-tv",
        "https://consumet-api-clone.vercel.app/anime/zoro/info?id=jujutsu-kaisen-534"
    ]
    async with httpx.AsyncClient(timeout=10) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url} -> {resp.status_code}")
            except Exception as e:
                print(f"{url} -> Error: {e}")

asyncio.run(test())
