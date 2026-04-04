import asyncio
import httpx
from AniVerseApiUrl.app.providers.gogoanime import GogoAnimeProvider

async def main():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient() as client:
        print("Servers SUB:", await p.get_servers(client, "my-star-season-2-episode-1", "sub"))
        print("Servers DUB:", await p.get_servers(client, "my-star-season-2-dub-episode-1", "dub"))
        print("Amagami SUB:", await p.get_servers(client, "tying-the-knot-with-an-amagami-sister-episode-1", "sub"))
        print("Amagami DUB:", await p.get_servers(client, "tying-the-knot-with-an-amagami-sister-dub-episode-1", "dub"))

asyncio.run(main())
