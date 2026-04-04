import asyncio
import httpx
import re

async def main():
    async with httpx.AsyncClient() as client:
        # Search by romaji title
        search_url = "https://anitaku.to/search.html?keyword=Oshi%20no%20Ko"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches for Oshi no Ko:", matches)

asyncio.run(main())
