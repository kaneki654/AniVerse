import asyncio
import httpx
import re

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://vidsrc.cc/v2/embed/tv/1429/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        
        # We need to extract the sources/subtitles from the page
        print("Body preview:", resp.text[:500])
        # search for source or player setup
        match = re.search(r'source:\s*"([^"]+)"', resp.text)
        if match:
            print("Source:", match.group(1))

asyncio.run(run())
