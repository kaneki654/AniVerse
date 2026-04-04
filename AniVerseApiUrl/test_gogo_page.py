import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/attack-on-titan")
        print("Status:", r.status_code)
        tree = HTMLParser(r.text)
        print("Title:", tree.css_first("h1").text())
        for a in tree.css("a"):
            text = a.text()
            if "dub" in text.lower():
                print("Found dub link:", text, "->", a.attributes.get("href"))

asyncio.run(run())
