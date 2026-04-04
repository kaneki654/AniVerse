import asyncio
import httpx
import re

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        url = "https://vidsrc.me/embed/tv/85937/1/1"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
        iframe_src = "https:" + match.group(1) if match and match.group(1).startswith("//") else match.group(1)
        
        parsed_url = httpx.URL(iframe_src)
        base_host = f"{parsed_url.scheme}://{parsed_url.netloc}"
        
        resp2 = await client.get(iframe_src, headers={"Referer": "https://vidsrc.me/"})
        match = re.search(r"src:\s*'(/prorcp/[^']+)'", resp2.text)
        prorcp_url = base_host + match.group(1) if match else None
        
        resp3 = await client.get(prorcp_url, headers={"Referer": base_host + "/"})
        
        m3u8_match = re.search(r'file:\s*"([^"]+)"', resp3.text)
        if m3u8_match:
            raw_m3u8 = m3u8_match.group(1)
            urls = raw_m3u8.split(" or ")
            master_url = urls[0].replace("{v1}", parsed_url.netloc)
            print("Streams:", [{"url": master_url, "quality": "auto"}])
            
        subs_match = re.search(r'subtitle:\s*"([^"]+)"', resp3.text)
        subtitles = []
        if subs_match:
            raw_subs = subs_match.group(1)
            # Format: [English]https://...vtt,[Spanish]https://...vtt
            subs_list = raw_subs.split(",")
            for s in subs_list:
                m = re.search(r'\[(.*?)\](.*)', s)
                if m:
                    subtitles.append({"file": m.group(2), "label": m.group(1), "kind": "captions"})
        print("Subtitles:", subtitles)

asyncio.run(run())
