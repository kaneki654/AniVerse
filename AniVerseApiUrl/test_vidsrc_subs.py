import asyncio
import httpx
from app.providers.vidsrc import VidSrcProvider
import re

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://vidsrc.me/embed/tv/85937/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
        iframe_src = match.group(1) if match else None
        if iframe_src and iframe_src.startswith("//"):
            iframe_src = "https:" + iframe_src
        print("Iframe:", iframe_src)
        
        resp2 = await client.get(iframe_src, headers={"Referer": "https://vidsrc.me/"})
        match = re.search(r"src:\s*'(/prorcp/[^']+)'", resp2.text)
        prorcp_url = "https://vidsrc.stream" + match.group(1) if match else None
        print("Prorcp:", prorcp_url)
        
        if prorcp_url:
            resp3 = await client.get(prorcp_url, headers={"Referer": "https://vidsrc.stream/"})
            print("Subtitles in setup?", "subtitle" in resp3.text.lower() or ".vtt" in resp3.text.lower() or "tracks" in resp3.text.lower())
            
            subs_match = re.search(r'subtitle:\s*"([^"]+)"', resp3.text)
            if subs_match:
                print("Subtitles found:", subs_match.group(1))

asyncio.run(run())
