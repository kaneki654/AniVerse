import asyncio
import httpx
import re

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://vidsrc.cc/v2/embed/tv/1429/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        for line in resp.text.split('\n'):
            if 'source' in line.lower() or 'track' in line.lower() or 'subtitle' in line.lower() or 'file' in line.lower():
                print(line.strip()[:200])

asyncio.run(run())
