import asyncio
import httpx
import json

async def test():
    apis = [
        "https://api-aniwatch.onrender.com/anime/search?q=jujutsu",
        "https://api-aniwatch.onrender.com/api/v2/hianime/search?q=jujutsu",
        "https://hianime-api.vercel.app/api/v2/hianime/search?q=jujutsu",
        "https://hianime-api.vercel.app/anime/search?q=jujutsu"
    ]
    async with httpx.AsyncClient(timeout=10) as client:
        for url in apis:
            try:
                resp = await client.get(url)
                print(f"{url} -> {resp.status_code}")
                if resp.status_code == 200:
                    print(resp.json().keys())
            except Exception as e:
                print(f"{url} -> Error: {e}")

asyncio.run(test())
