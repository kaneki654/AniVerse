import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, 'tying-the-knot-with-an-amagami-sister', 1)
        servers = await p.get_servers(client, ep, category='dub')
        print("Servers:", [s["name"] for s in servers])
        
        extracted = await p.extract(client, servers)
        print("Extracted:", extracted)

asyncio.run(run())
