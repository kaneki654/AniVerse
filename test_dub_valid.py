import asyncio
import httpx
from selectolax.parser import HTMLParser

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://anitaku.to/my-star-season-2-dub-episode-1")
        tree = HTMLParser(r.text)
        print("Title:", tree.css_first("title").text() if tree.css_first("title") else "No title")
        h1 = tree.css_first("h1")
        print("H1:", h1.text() if h1 else "No h1")
        
        # Check error class
        error = tree.css_first(".error")
        if error:
            print("Error message:", error.text(strip=True))
            
asyncio.run(main())
