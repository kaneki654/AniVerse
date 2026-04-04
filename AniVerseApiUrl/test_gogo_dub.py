import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def main():
    provider = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        slug = await provider.map_anime(client, "16498", "dub")
        print("MAPPED SLUG:", slug)

asyncio.run(main())
