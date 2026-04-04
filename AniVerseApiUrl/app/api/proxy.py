from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import StreamingResponse, Response
import httpx
import logging
import re

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
async def proxy_m3u8(url: str, request: Request):
    """
    Proxy an M3U8 playlist and rewrite all absolute URLs so the TS chunks 
    are forced through the backend stream proxy to bypass CORS/Cloudflare.
    """
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://cloudnestra.com/"
    }
    
    async with httpx.AsyncClient(headers=headers, timeout=15) as client:
        try:
            r = await client.get(url)
            if r.status_code != 200:
                raise HTTPException(status_code=r.status_code, detail="Failed to fetch m3u8")
                
            content = r.text
            
            # Rewrite any line starting with http:// or https:// to point to our stream proxy
            base_proxy = str(request.base_url) + "proxy/stream?url="
            # Using a simple line-by-line replacement
            rewritten_lines = []
            for line in content.splitlines():
                stripped = line.strip()
                if stripped.startswith("http"):
                    # Use absolute URL to the proxy
                    rewritten_lines.append(f"{base_proxy}{stripped}")
                else:
                    rewritten_lines.append(line)
                    
            rewritten_content = "\n".join(rewritten_lines)
            
            return Response(content=rewritten_content, media_type="application/vnd.apple.mpegurl")
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))

@router.get("/stream")
async def proxy_stream(url: str, request: Request):
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
        
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        "Referer": "https://cloudnestra.com/"
    }
    
    return StreamingResponse(stream_proxy(url, headers), media_type="video/mp2t")
