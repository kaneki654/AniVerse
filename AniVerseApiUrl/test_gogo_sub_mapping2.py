import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Test 164172 (Amagami Sister) sub
        slug = await p.map_anime(client, "164172", "sub")
        print("Amagami sub slug:", slug)
        
        # Test 164172 dub
        slug2 = await p.map_anime(client, "164172", "dub")
        print("Amagami dub slug:", slug2)
        
        # What about Jujutsu Kaisen S2 (16498 is AOT, JJK S2 is 163134 or something)
        # Let's test "Mashle" or something with a known -dub
        slug3 = await p.map_anime(client, "153288", "sub")  # Mashle
        print("Mashle sub slug:", slug3)
        slug4 = await p.map_anime(client, "153288", "dub")
        print("Mashle dub slug:", slug4)

asyncio.run(run())
