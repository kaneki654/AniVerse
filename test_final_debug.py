import asyncio
import httpx
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        print("166531 map_anime sub:", await p.map_anime(client, "166531", "sub"))
        print("166531 map_anime dub:", await p.map_anime(client, "166531", "dub"))
        
        print("164172 map_anime sub:", await p.map_anime(client, "164172", "sub"))
        print("164172 map_anime dub:", await p.map_anime(client, "164172", "dub"))

asyncio.run(main())
