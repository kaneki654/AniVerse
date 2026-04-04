import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/oshi-no-ko-season-3")
        tree = HTMLParser(r.text)
        print("oshi-no-ko-season-3 title:", tree.css_first("h1").text() if tree.css_first("h1") else "Not found")

        r2 = await client.get("https://anitaku.to/category/my-star-season-2")
        tree2 = HTMLParser(r2.text)
        print("my-star-season-2 title:", tree2.css_first("h1").text() if tree2.css_first("h1") else "Not found")

asyncio.run(main())
