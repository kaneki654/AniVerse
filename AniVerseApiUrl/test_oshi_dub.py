import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, 'my-star-season-2', 1)
        servers = await p.get_servers(client, ep, category='dub')
        print("Servers for Oshi no Ko S2 DUB:", [s["name"] for s in servers])

asyncio.run(run())
