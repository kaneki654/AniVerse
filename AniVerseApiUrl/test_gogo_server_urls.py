import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, "attack-on-titan", 1)
        servers_sub = await p.get_servers(client, ep, category="sub")
        print("AOT sub urls:", [s["url"] for s in servers_sub])
        
        servers_dub = await p.get_servers(client, ep, category="dub")
        print("AOT dub urls:", [s["url"] for s in servers_dub])

asyncio.run(run())
