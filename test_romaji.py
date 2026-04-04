import asyncio
import httpx
import re
import urllib.parse

async def main():
    async with httpx.AsyncClient() as client:
        romaji = "[Oshi no Ko] 2nd Season"
        search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(romaji)}"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches for Romaji:", matches)
        
        # What if we strip brackets?
        romaji_clean = "Oshi no Ko 2nd Season"
        search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(romaji_clean)}"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches for Cleaned Romaji:", matches)

asyncio.run(main())
