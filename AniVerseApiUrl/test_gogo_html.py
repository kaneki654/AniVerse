import asyncio
import httpx
from selectolax.parser import HTMLParser

async def run():
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # AOT Episode 1
        resp = await client.get("https://anitaku.to/attack-on-titan-episode-1", headers={"User-Agent": "Mozilla/5.0"})
        tree = HTMLParser(resp.text)
        
        div_sub = tree.css_first("div.type_SUB")
        print("type_SUB found?", bool(div_sub))
        div_dub = tree.css_first("div.type_DUB")
        print("type_DUB found?", bool(div_dub))
        
        anime_muti_link = tree.css(".anime_muti_link")
        print("anime_muti_link count:", len(anime_muti_link))

asyncio.run(run())
