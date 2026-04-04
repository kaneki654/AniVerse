import asyncio
import httpx
import urllib.parse
import re

async def run():
    title = "shingeki no kyojin"
    search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(title)}"
    async with httpx.AsyncClient() as client:
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches:", matches)

asyncio.run(run())
