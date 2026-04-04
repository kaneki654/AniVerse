import asyncio
import httpx

async def test():
    urls = [
        "https://api-aniwatch.onrender.com/anime/search?q=jujutsu",
        "https://anime-api-v2.vercel.app/anime/gogoanime/naruto",
        "https://anify.anify.tv/search/anime/jujutsu",
        "https://api.amvstr.me/api/v2/search?q=jujutsu",
    ]
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code}")
                if resp.status_code == 200:
                    print(resp.text[:100])
            except Exception as e:
                print(f"{url}: Error {e}")

asyncio.run(test())
