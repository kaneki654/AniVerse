import asyncio
import httpx
import re

async def main():
    async with httpx.AsyncClient() as client:
        # Search by Title
        search_url = "https://anitaku.to/search.html?keyword=Oshi%20no%20Ko%20Season%202"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches))
        print("Matches for Oshi no Ko Season 2:", matches)
        
        # Try search for Amagami Sister just in case
        search_url = "https://anitaku.to/search.html?keyword=Tying%20the%20Knot%20with%20an%20Amagami%20Sister"
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        matches2 = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches2 = list(dict.fromkeys(matches2))
        print("Matches for Amagami:", matches2)

asyncio.run(main())
