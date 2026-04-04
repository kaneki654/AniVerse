import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/tying-the-knot-with-an-amagami-sister-episode-1")
        print(f"Amagami sub status: {r.status_code}")
        r2 = await client.get("https://anitaku.to/tying-the-knot-with-an-amagami-sister-dub-episode-1")
        print(f"Amagami dub status: {r2.status_code}")
        
        # Check if sub has dub div
        tree = HTMLParser(r.text)
        div_dub = tree.css_first("div.type_DUB")
        if div_dub:
            print("Amagami sub has div.type_DUB")
        else:
            print("Amagami sub DOES NOT have div.type_DUB")

asyncio.run(main())
