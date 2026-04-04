import asyncio
import httpx
import re

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        # AOT is TMDB 1429. Episode 1.
        url = "https://vidsrc.cc/v2/embed/tv/1429/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        print("vidsrc.cc status:", resp.status_code)
        
        # Test vidsrc.pro
        url2 = "https://vidsrc.pro/embed/tv/1429/1/1"
        resp2 = await client.get(url2, headers={"User-Agent": "Mozilla/5.0"})
        print("vidsrc.pro status:", resp2.status_code)

asyncio.run(run())
