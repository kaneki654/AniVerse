import asyncio
import httpx
import urllib.parse
import re

async def run():
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote('Attack on Titan')}"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches)) # Remove duplicates
        print("AOT Matches:", matches)
        
        search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote('Shingeki no Kyojin')}"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches)) # Remove duplicates
        print("Shingeki no Kyojin Matches:", matches)

asyncio.run(run())
