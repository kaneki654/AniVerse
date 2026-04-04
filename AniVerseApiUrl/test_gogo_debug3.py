import asyncio
import httpx
from bs4 import BeautifulSoup

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://anitaku.to/attack-on-titan-episode-1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        print("Status:", resp.status_code)
        print("Servers html:")
        
        from selectolax.parser import HTMLParser
        tree = HTMLParser(resp.text)
        
        for li in tree.css(".anime_muti_link ul li"):
            embed_link = li.attributes.get("data-video")
            server_name = li.attributes.get("class", "unknown")
            print(server_name, embed_link)

asyncio.run(run())
