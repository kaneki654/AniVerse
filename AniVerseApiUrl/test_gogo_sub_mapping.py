import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Let's test a popular anime like Attack on Titan
        slug = await p.map_anime(client, "16498", "sub")
        print("AOT sub slug:", slug)
        
        slug_dub = await p.map_anime(client, "16498", "dub")
        print("AOT dub slug:", slug_dub)
        
        # Test another one that might be problematic, maybe Oshi no Ko
        slug2 = await p.map_anime(client, "164172", "sub")
        print("Amagami Sister sub slug:", slug2)
        
        slug2_dub = await p.map_anime(client, "164172", "dub")
        print("Amagami Sister dub slug:", slug2_dub)

asyncio.run(run())
