import asyncio
import httpx
import urllib.parse
import re

async def run():
    title = "Attack on Titan dub"
    search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(title)}"
    async with httpx.AsyncClient() as client:
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches dub:", matches)

        title2 = "Shingeki no Kyojin dub"
        search_url2 = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(title2)}"
        search_resp2 = await client.get(search_url2, headers={"User-Agent": "Mozilla/5.0"})
        matches2 = re.findall(r'href="/category/([^"]+)"', search_resp2.text)
        matches2 = list(dict.fromkeys(matches2))
        print("Matches2 dub:", matches2)

asyncio.run(run())
