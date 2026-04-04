import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/shingeki-no-kyojin-dub-episode-1", follow_redirects=True)
        if "Pages not found" not in r.text:
            print("FOUND EPISODE!")
        else:
            print("Not found")
            
asyncio.run(run())
