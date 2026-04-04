import asyncio
import httpx
from selectolax.parser import HTMLParser
import urllib.parse

async def run():
    title = "Shingeki no Kyojin"
    search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(title)}"
    async with httpx.AsyncClient() as client:
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        tree = HTMLParser(search_resp.text)
        for li in tree.css(".items li"):
            name = li.css_first(".name a").text()
            link = li.css_first(".name a").attributes.get("href")
            print(f"{name} -> {link}")

asyncio.run(run())
