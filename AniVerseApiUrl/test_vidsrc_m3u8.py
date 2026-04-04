import asyncio
import httpx
from app.providers.vidsrc import VidSrcProvider
import re
from app.extractors.m3u8_parser import M3U8Parser

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://vidsrc.me/embed/tv/85937/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
        iframe_src = "https:" + match.group(1) if match and match.group(1).startswith("//") else match.group(1)
        
        resp2 = await client.get(iframe_src, headers={"Referer": "https://vidsrc.me/"})
        match = re.search(r"src:\s*'(/prorcp/[^']+)'", resp2.text)
        prorcp_url = "https://vidsrc.stream" + match.group(1) if match else None
        
        if prorcp_url:
            resp3 = await client.get(prorcp_url, headers={"Referer": "https://vidsrc.stream/"})
            m3u8_match = re.search(r'file:\s*"([^"]+)"', resp3.text)
            if m3u8_match:
                master_url = m3u8_match.group(1).split(" or ")[0].replace("{v1}", "vidsrc.stream")
                print("Master M3U8:", master_url)
                resp_m3u8 = await client.get(master_url, headers={"Referer": "https://vidsrc.stream/"})
                print("--- M3U8 Content ---")
                print(resp_m3u8.text[:500])
                print("--------------------")

asyncio.run(run())
