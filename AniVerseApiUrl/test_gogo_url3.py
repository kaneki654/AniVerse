import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/shingeki-no-kyojin-dub", follow_redirects=True)
        if "Pages not found" in r.text:
            print("Not found")
        else:
            print("Found!", r.status_code)
            
asyncio.run(run())
