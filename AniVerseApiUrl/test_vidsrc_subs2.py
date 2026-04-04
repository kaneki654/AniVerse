import asyncio
import httpx
import re

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
            # Let's search for 'subtitle' or 'tracks'
            for line in resp3.text.split('\n'):
                if 'subtitle' in line.lower() or 'tracks' in line.lower() or '.vtt' in line.lower() or '.srt' in line.lower():
                    print("Found line:", line.strip())

asyncio.run(run())
