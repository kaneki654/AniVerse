import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        r = await client.head("https://anitaku.to/category/oshi-no-ko-2nd-season-dub", follow_redirects=True)
        print("HEAD status:", r.status_code)
        
asyncio.run(test())
