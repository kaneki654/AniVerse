import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/my-star-season-2-dub")
        tree = HTMLParser(r.text)
        print("Status code:", r.status_code)
        print("Title:", tree.css_first("title").text() if tree.css_first("title") else "No title")

asyncio.run(main())
