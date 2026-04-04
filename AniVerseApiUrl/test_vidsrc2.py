import asyncio
import httpx
from bs4 import BeautifulSoup
import re
import urllib.parse
import base64

async def test():
    url = "https://vidsrc.me/embed/tv/82684/1/1"
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
            if match:
                iframe_src = match.group(1)
                if iframe_src.startswith("//"):
                    iframe_src = "https:" + iframe_src
                print("Found iframe:", iframe_src)
                
                resp2 = await client.get(iframe_src, headers={"User-Agent": "Mozilla/5.0", "Referer": url})
                print("Iframe Status:", resp2.status_code)
                
                # Check what is inside iframe
                with open("vidsrc_iframe2.html", "w") as f:
                    f.write(resp2.text)
                    
                # Search for data attribute or script
                print("Length:", len(resp2.text))
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
