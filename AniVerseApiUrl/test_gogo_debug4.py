import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://anitaku.to/attack-on-titan-episode-1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        tree = HTMLParser(resp.text)
        
        for li in tree.css(".anime_muti_link ul li"):
            print(li.html)

asyncio.run(run())
