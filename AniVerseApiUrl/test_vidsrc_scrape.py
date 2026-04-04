import asyncio
import httpx
from bs4 import BeautifulSoup
import re

async def test():
    url = "https://vidsrc.me/embed/tv/95479/1/1"
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            with open("vidsrc.html", "w") as f:
                f.write(resp.text)
            
            # They usually use an iframe to a specific server like rcp.vidsrc.me
            match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
            if match:
                iframe_src = match.group(1)
                if iframe_src.startswith("//"):
                    iframe_src = "https:" + iframe_src
                print("Found iframe:", iframe_src)
                
                resp2 = await client.get(iframe_src, headers={"User-Agent": "Mozilla/5.0", "Referer": url})
                print("Iframe Status:", resp2.status_code)
                with open("vidsrc_iframe.html", "w") as f:
                    f.write(resp2.text)
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
