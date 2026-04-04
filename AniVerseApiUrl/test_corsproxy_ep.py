import asyncio
import httpx
import urllib.parse
from selectolax.parser import HTMLParser

async def test():
    target = "https://anitaku.pe/jujutsu-kaisen-tv-episode-1"
    url = f"https://corsproxy.io/?url={urllib.parse.quote(target)}"
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            with open("ep.html", "w") as f:
                f.write(resp.text)
            tree = HTMLParser(resp.text)
            links = tree.css(".anime_muti_link ul li")
            print("Found .anime_muti_link ul li:", len(links))
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
