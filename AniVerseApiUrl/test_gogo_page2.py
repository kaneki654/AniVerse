import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/shingeki-no-kyojin")
        print("Status:", r.status_code)
        if "Pages not found" in r.text:
            print("Not found")
        else:
            tree = HTMLParser(r.text)
            title = tree.css_first("h1")
            print("Title:", title.text() if title else "No title")

asyncio.run(run())
