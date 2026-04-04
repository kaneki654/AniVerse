import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # AOT Episode 1
        resp = await client.get("https://anitaku.to/attack-on-titan-episode-1", headers={"User-Agent": "Mozilla/5.0"})
        tree = HTMLParser(resp.text)
        
        div_sub = tree.css_first("div.type_SUB")
        if div_sub:
            print("SUB links:")
            for a in div_sub.css("ul li a"):
                print(a.text(strip=True), a.attributes.get("data-video"))
                
        div_dub = tree.css_first("div.type_DUB")
        if div_dub:
            print("\nDUB links:")
            for a in div_dub.css("ul li a"):
                print(a.text(strip=True), a.attributes.get("data-video"))

asyncio.run(run())
