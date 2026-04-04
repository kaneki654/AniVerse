import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, 'tying-the-knot-with-an-amagami-sister', 1)
        servers = await p.get_servers(client, ep, category='dub')
        
        extracted = await p.extract(client, servers)
        dood_url = next((s["url"] for s in extracted.get("streams", []) if "cloudatacdn" in s["url"]), None)
        
        if not dood_url:
            print("No Doodstream URL found")
            return
            
        print("Dood URL:", dood_url)
        
        # Test without Referer
        print("\n--- Testing Doodstream MP4 with NO Referer ---")
        try:
            r1 = await client.head(dood_url)
            print("Status:", r1.status_code)
        except Exception as e:
            print("Failed:", e)
            
        # Test with Doodstream Referer
        print("\n--- Testing Doodstream MP4 with Referer ---")
        try:
            r2 = await client.head(dood_url, headers={"Referer": "https://myvidplay.com/"})
            print("Status:", r2.status_code)
        except Exception as e:
            print("Failed:", e)

asyncio.run(run())
