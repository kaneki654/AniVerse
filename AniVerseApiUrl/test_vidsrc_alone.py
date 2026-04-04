import asyncio
import httpx
from app.providers.vidsrc import VidSrcProvider

async def run():
    p = VidSrcProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        res = await p.resolve("164172", 1)
        print("VidSrc result:", res)

asyncio.run(run())
