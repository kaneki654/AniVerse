import asyncio
import httpx

async def test():
    urls = [
        "https://consumet-api-clone.vercel.app/",
        "https://api.consumet.org/",
        "https://anify.anify.tv/",
        "https://api.malsync.moe/mal/anime/40748",
        "https://api.ani.zip/mappings?anilist_id=101280"
    ]
    async with httpx.AsyncClient(timeout=5) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code}")
            except Exception as e:
                print(f"{url}: Error")

asyncio.run(test())
