import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/my-star-season-2-episode-1")
        tree = HTMLParser(r.text)
        
        div_dub = tree.css_first("div.type_DUB")
        if div_dub:
            print("my-star has div.type_DUB")
        else:
            print("my-star NO div.type_DUB")
            
asyncio.run(main())
