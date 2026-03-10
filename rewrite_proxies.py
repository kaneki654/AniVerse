with open('app/main.py', 'r') as f:
    lines = f.readlines()

# Find where @app.get("/proxy/m3u8") starts
start_idx = -1
for i, line in enumerate(lines):
    if line.startswith('@app.get("/proxy/m3u8")'):
        start_idx = i
        break

if start_idx != -1:
    lines = lines[:start_idx]

# Append the new streaming proxy functions
lines.append('@app.get("/proxy/m3u8")\n')
lines.append('async def proxy_m3u8(url: str, referer: str = None):\n')
lines.append('    headers = {"User-Agent": USER_AGENT}\n')
lines.append('    if referer:\n')
lines.append('        headers["Referer"] = referer\n')
lines.append('        headers["Origin"] = referer.rstrip("/")\n')
lines.append('    \n')
lines.append('    async def stream_m3u8():\n')
lines.append('        async with httpx.AsyncClient() as client:\n')
lines.append('            try:\n')
lines.append('                async with client.stream("GET", url, headers=headers) as response:\n')
lines.append('                    async for chunk in response.aiter_bytes():\n')
lines.append('                        yield chunk\n')
lines.append('            except Exception as e:\n')
lines.append('                print(f"Proxy M3U8 Error: {e}")\n')
lines.append('                yield b"Proxy Error"\n')
lines.append('    \n')
lines.append('    return StreamingResponse(stream_m3u8(), media_type="application/vnd.apple.mpegurl")\n\n')

lines.append('@app.get("/proxy/subtitle")\n')
lines.append('async def proxy_subtitle(url: str, referer: str = None):\n')
lines.append('    headers = {"User-Agent": USER_AGENT}\n')
lines.append('    if referer:\n')
lines.append('        headers["Referer"] = referer\n')
lines.append('        headers["Origin"] = referer.rstrip("/")\n')
lines.append('    \n')
lines.append('    async def stream_subtitle():\n')
lines.append('        async with httpx.AsyncClient() as client:\n')
lines.append('            try:\n')
lines.append('                async with client.stream("GET", url, headers=headers) as response:\n')
lines.append('                    async for chunk in response.aiter_bytes():\n')
lines.append('                        yield chunk\n')
lines.append('            except Exception as e:\n')
lines.append('                print(f"Proxy Subtitle Error: {e}")\n')
lines.append('                yield b"Proxy Error"\n')
lines.append('    \n')
lines.append('    return StreamingResponse(stream_subtitle(), media_type="text/vtt")\n')

with open('app/main.py', 'w') as f:
    f.writelines(lines)
