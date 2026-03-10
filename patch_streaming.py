import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Replace proxy_m3u8 returning `Response(...)` with streaming
streaming_m3u8 = """@app.get("/proxy/m3u8")
async def proxy_m3u8(url: str, referer: str = None):
    headers = {
        "User-Agent": USER_AGENT
    }
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
        
    print(f"PROXY M3U8 FETCHING: {url} | HEADERS: {headers}")
    
    async def stream_m3u8():
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                print(f"Proxy M3U8 Error: {e}")
                yield b"Proxy Error"

    return StreamingResponse(stream_m3u8(), media_type="application/vnd.apple.mpegurl")"""

streaming_subtitle = """@app.get("/proxy/subtitle")
async def proxy_subtitle(url: str, referer: str = None):
    headers = {
        "User-Agent": USER_AGENT
    }
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
        
    print(f"PROXY SUBTITLE FETCHING: {url} | HEADERS: {headers}")
    
    async def stream_subtitle():
        async with httpx.AsyncClient() as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                print(f"Proxy Subtitle Error: {e}")
                yield b"Proxy Error"

    return StreamingResponse(stream_subtitle(), media_type="text/vtt")"""

# Let's replace the whole proxy blocks we just added with these.
# I'll just rewrite the file from scratch from line 551 downwards.
