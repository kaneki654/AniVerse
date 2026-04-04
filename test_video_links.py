import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/my-star-season-2-dub-episode-1")
        tree = HTMLParser(r.text)
        
        links = tree.css("a[data-video]")
        print("Dub links:", len(links))
        for link in links:
            print(link.attributes.get('data-video'), link.text(strip=True))

asyncio.run(main())
