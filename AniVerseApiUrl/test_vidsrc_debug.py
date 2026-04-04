import asyncio
import httpx
import re
from urllib.parse import urlparse

async def run():
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        # Get episode ID using the TMDB ID
        url = "https://vidsrc.me/embed/tv/234910/1/1"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
        
        resp = await client.get(url, headers=headers)
        match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
        if not match:
            print("No iframe found!")
            return
            
        iframe_url = match.group(1)
        if iframe_url.startswith("//"):
            iframe_url = "https:" + iframe_url
            
        print("Iframe URL:", iframe_url)
        
        parsed_url = urlparse(iframe_url)
        base_host = f"{parsed_url.scheme}://{parsed_url.netloc}"
        
        resp = await client.get(iframe_url, headers={"Referer": "https://vidsrc.me/"})
        print("Iframe Status:", resp.status_code)
        
        match = re.search(r"src:\s*'(/prorcp/[^']+)'", resp.text)
        if not match:
            print("Prorcp not found!")
            return
            
        prorcp_url = base_host + match.group(1)
        print("Prorcp URL:", prorcp_url)
        
        resp2 = await client.get(prorcp_url, headers={"Referer": base_host + "/"})
        print("Prorcp Status:", resp2.status_code)
        
        m3u8_match = re.search(r'file:\s*"([^"]+)"', resp2.text)
        if m3u8_match:
            raw_m3u8 = m3u8_match.group(1)
            urls = raw_m3u8.split(" or ")
            if urls:
                master_url = urls[0].replace("{v1}", parsed_url.netloc)
                print("Found stream:", master_url)
                
            subs_match = re.search(r'subtitle:\s*"([^"]+)"', resp2.text)
            if subs_match:
                print("Found subs:", subs_match.group(1))
            else:
                print("No subtitles found.")
        else:
            print("No m3u8 found in prorcp")

asyncio.run(run())
