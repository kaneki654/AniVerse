import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://anitaku.to/oshi-no-ko-season-3-episode-1", headers={"User-Agent": "Mozilla/5.0"})
        tree = HTMLParser(resp.text)
        
        div_dub = tree.css_first("div.type_DUB")
        if div_dub:
            print("Found div.type_DUB")
            print(div_dub.html)
        else:
            print("div.type_DUB NOT FOUND")
            
        div_sub = tree.css_first("div.type_SUB")
        if div_sub:
            print("Found div.type_SUB")
            print(div_sub.html)
            
asyncio.run(main())
