import asyncio
import httpx
from bs4 import BeautifulSoup
import re

async def test():
    with open("vidsrc_iframe2.html", "r") as f:
        html = f.read()
    match = re.search(r"src:\s*'(/prorcp/[^']+)'", html)
    if match:
        prorcp_url = "https://cloudnestra.com" + match.group(1)
        print("Prorcp URL:", prorcp_url)
        
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(prorcp_url, headers={"User-Agent": "Mozilla/5.0", "Referer": "https://cloudnestra.com/"})
            print("Status:", resp.status_code)
            with open("prorcp.html", "w") as f2:
                f2.write(resp.text)
            print("Length:", len(resp.text))

asyncio.run(test())
