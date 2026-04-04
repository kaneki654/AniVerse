import asyncio
import httpx
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        servers = await p.get_servers(client, "my-star-season-2-episode-1", "sub")
        print(servers)
        
asyncio.run(main())
