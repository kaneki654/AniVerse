import re

with open('app/main.py', 'r') as f:
    content = f.read()

idx = content.find('@app.get("/proxy/m3u8")')
if idx != -1:
    base_content = content[:idx]
else:
    base_content = content + "\n"

new_code = """@app.get("/proxy/m3u8")
async def proxy_m3u8(url: str, referer: str = None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(url, headers=headers)
            content = resp.text
            
            lines = content.split('\\n')
            rewritten_lines = []
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                if line.startswith('#'):
                    if 'URI="' in line:
                        def replace_uri(match):
                            uri = match.group(1)
                            abs_uri = urljoin(url, uri)
                            if abs_uri.split('?')[0].endswith('.m3u8'):
                                proxy_uri = f"/proxy/m3u8?url={quote(abs_uri, safe='')}&referer={quote(referer or '', safe='')}"
                            else:
                                proxy_uri = f"/proxy/ts?url={quote(abs_uri, safe='')}&referer={quote(referer or '', safe='')}"
                            return f'URI="{proxy_uri}"'
                        line = re.sub(r'URI="([^"]+)"', replace_uri, line)
                    rewritten_lines.append(line)
                else:
                    abs_url = urljoin(url, line)
                    if abs_url.split('?')[0].endswith('.m3u8'):
                        proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer or '', safe='')}"
                    else:
                        proxy_url = f"/proxy/ts?url={quote(abs_url, safe='')}&referer={quote(referer or '', safe='')}"
                    rewritten_lines.append(proxy_url)
            
            return Response(content='\\n'.join(rewritten_lines), media_type="application/vnd.apple.mpegurl")
        except Exception as e:
            print(f"Proxy M3U8 Error: {e}")
            return Response(status_code=500, content="Proxy Error")

@app.get("/proxy/ts")
async def proxy_ts(url: str, referer: str = None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    
    async def stream_ts():
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                print(f"Proxy TS Error: {e}")
                yield b"Proxy Error"
                
    return StreamingResponse(stream_ts(), media_type="video/mp2t")

@app.get("/proxy/subtitle")
async def proxy_subtitle(url: str, referer: str = None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    
    async def stream_subtitle():
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                print(f"Proxy Subtitle Error: {e}")
                yield b"Proxy Error"
    
    return StreamingResponse(stream_subtitle(), media_type="text/vtt")
"""

with open('app/main.py', 'w') as f:
    f.write(base_content + new_code)
