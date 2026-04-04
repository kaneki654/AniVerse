import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Add StreamingResponse import if not there
if "from fastapi.responses import" in content and "StreamingResponse" not in content:
    content = content.replace("from fastapi.responses import", "from fastapi.responses import StreamingResponse, ")

new_endpoint = """
@app.get("/proxy/stream")
async def proxy_stream(request: Request, url: str, referer: str = None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
        
    # Forward the Range header from the client
    range_header = request.headers.get("Range")
    if range_header:
        headers["Range"] = range_header

    async def stream_generator():
        async with httpx.AsyncClient(timeout=30.0) as client:
            async with client.stream("GET", url, headers=headers) as response:
                async for chunk in response.aiter_bytes(chunk_size=8192):
                    yield chunk

    # We need to make a HEAD request first to get the content length and type, unless we fetch it immediately
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            head_resp = await client.head(url, headers=headers)
            
        resp_headers = {}
        for key in ["Accept-Ranges", "Content-Length", "Content-Type", "Content-Range"]:
            if key in head_resp.headers:
                resp_headers[key] = head_resp.headers[key]
                
        status_code = head_resp.status_code
        if status_code not in [200, 206]:
            # fallback to 200 if head fails weirdly
            status_code = 206 if range_header else 200

        return StreamingResponse(
            stream_generator(),
            status_code=status_code,
            headers=resp_headers,
            media_type=head_resp.headers.get("Content-Type", "video/mp4")
        )
    except Exception as e:
        print(f"Proxy Stream Error: {e}")
        return Response(status_code=500, content="Proxy Stream Error")
"""

# Let's insert it before @app.get("/proxy/m3u8")
if "@app.get(\"/proxy/stream\")" not in content:
    content = content.replace('@app.get("/proxy/m3u8")', new_endpoint + '\n@app.get("/proxy/m3u8")')
    
    # Also update get_source to use /proxy/stream for mp4s
    old_source = """                # Do NOT proxy premilkyway.com streams because they use tokenized IPs/Cookies
                if "premilkyway.com" in abs_url:
                    proxy_url = abs_url
                elif "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url"""
                    
    new_source = """                # Do NOT proxy premilkyway.com streams because they use tokenized IPs/Cookies
                if "premilkyway.com" in abs_url:
                    proxy_url = abs_url
                elif "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    # It's an mp4 like Doodstream, proxy it using our stream endpoint!
                    proxy_url = f"/proxy/stream?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
"""
    content = content.replace(old_source, new_source)

    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Added proxy_stream and updated get_source!")
else:
    print("proxy_stream already exists.")
