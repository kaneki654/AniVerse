import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/category/attack-on-titan")
        tree = HTMLParser(r.text)
        type_div = tree.css(".type")
        for t in type_div:
            print(t.text())

asyncio.run(run())
