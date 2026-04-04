import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        slug = await p.map_anime(client, "16498", "sub")
        print("Slug:", slug)
        ep = await p.get_episode(client, slug, 1)
        print("Ep route:", ep)
        servers = await p.get_servers(client, ep)
        print("Servers:", servers)
        
        extracted = await p.extract(client, servers)
        print("Extracted:", extracted)

asyncio.run(run())
