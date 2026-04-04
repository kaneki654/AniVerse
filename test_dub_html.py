import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/my-star-season-2-dub-episode-1")
        tree = HTMLParser(r.text)
        
        div = tree.css_first(".anime_muti_link")
        if div:
            print("Found .anime_muti_link")
            print(div.html)
        else:
            print(".anime_muti_link NOT FOUND")
            
        print("Checking for muti_link...")
        div2 = tree.css_first(".muti_link")
        if div2:
            print("Found .muti_link")

asyncio.run(main())
