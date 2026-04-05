from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import StreamingResponse, Response
import httpx
import logging
import re
from urllib.parse import urljoin, quote

router = APIRouter(prefix="/proxy", tags=["Proxy"])
logger = logging.getLogger(__name__)

async def stream_proxy(url: str, headers: dict):
    async with httpx.AsyncClient(headers=headers, timeout=30) as client:
        try:
            async with client.stream("GET", url) as response:
                if response.status_code != 200:
                    yield b""
                    return
                async for chunk in response.aiter_bytes():
                    yield chunk
        except Exception as e:
            logger.error(f"Proxy stream error: {e}")
            yield b""

@router.get("/m3u8")
async def proxy_m3u8(url: str, request: Request, referer: str = None):
    """
    Proxy an M3U8 playlist and rewrite all absolute URLs so the TS chunks 
    are forced through the backend stream proxy to bypass CORS/Cloudflare.
    """
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": referer if referer else "https://cloudnestra.com/"
    }
    
    async with httpx.AsyncClient(headers=headers, timeout=15) as client:
        try:
            r = await client.get(url)
            if r.status_code != 200:
                raise HTTPException(status_code=r.status_code, detail="Failed to fetch m3u8")
                
            content = r.text
            
            base_m3u8_proxy = str(request.base_url) + "proxy/m3u8?url="
            base_stream_proxy = str(request.base_url) + "proxy/stream?url="
            referer_query = f"&referer={quote(referer, safe='')}" if referer else ""
            
            rewritten_lines = []
            for line in content.splitlines():
                stripped = line.strip()
                if not stripped:
                    rewritten_lines.append(line)
                    continue
                    
                if stripped.startswith("#"):
                    if 'URI="' in stripped:
                        def replace_uri(match):
                            uri = match.group(1)
                            abs_uri = urljoin(url, uri)
                            if abs_uri.split('?')[0].endswith('.m3u8'):
                                proxy_uri = f"{base_m3u8_proxy}{quote(abs_uri, safe='')}{referer_query}"
                            else:
                                proxy_uri = f"{base_stream_proxy}{quote(abs_uri, safe='')}{referer_query}"
                            return f'URI="{proxy_uri}"'
                        rewritten_line = re.sub(r'URI="([^"]+)"', replace_uri, line)
                        rewritten_lines.append(rewritten_line)
                    else:
                        rewritten_lines.append(line)
                else:
                    abs_url = urljoin(url, stripped)
                    if abs_url.split('?')[0].endswith('.m3u8'):
                        rewritten_lines.append(f"{base_m3u8_proxy}{quote(abs_url, safe='')}{referer_query}")
                    else:
                        rewritten_lines.append(f"{base_stream_proxy}{quote(abs_url, safe='')}{referer_query}")
                    
            rewritten_content = "\n".join(rewritten_lines)
            
            return Response(content=rewritten_content, media_type="application/vnd.apple.mpegurl")
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/stream")
async def proxy_stream(url: str, request: Request, referer: str = None):
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": referer if referer else "https://cloudnestra.com/"
    }
    
    return StreamingResponse(stream_proxy(url, headers), media_type="video/mp2t")

@router.get("/subtitle")
async def proxy_subtitle(url: str, referer: str = None):
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    
    async def stream_subtitle():
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    if response.status_code != 200:
                        yield b""
                        return
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                logger.error(f"Proxy Subtitle Error: {e}")
                yield b"WEBVTT\n\nProxy Error"
                
    return StreamingResponse(stream_subtitle(), media_type="text/vtt")

