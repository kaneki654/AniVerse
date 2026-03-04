import sys
import os
import re
from urllib.parse import urljoin, quote, unquote
from datetime import date as dt

# Add libs to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'libs')))

from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import httpx

app = FastAPI()

# Mount static files
app.mount("/static", StaticFiles(directory="app/static"), name="static")

# Setup templates
templates = Jinja2Templates(directory="app/templates")

API_BASE = "https://aniverseaniwatch.vercel.app/api/v2/hianime"
DEFAULT_REFERER = "https://hianime.to/"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_proxy_headers(referer: str = None):
    return {
        "User-Agent": USER_AGENT,
        "Referer": referer if referer else DEFAULT_REFERER,
        "Origin": referer if referer else DEFAULT_REFERER
    }

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/home")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="home.html", 
        context={"data": data}
    )

@app.get("/search/suggestion")
async def search_suggestion(q: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/search/suggestion?q={q}")
            return resp.json()
        except:
            return {"suggestions": []}

@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/search?q={q}&page={page}")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="search.html", 
        context={"data": data, "query": q, "page": page}
    )

@app.get("/anime/{anime_id}", response_class=HTMLResponse)
async def anime_detail(request: Request, anime_id: str):
    async with httpx.AsyncClient() as client:
        try:
            detail_resp = await client.get(f"{API_BASE}/anime/{anime_id}")
            detail_data = detail_resp.json()
            episodes_resp = await client.get(f"{API_BASE}/anime/{anime_id}/episodes")
            episodes_data = episodes_resp.json()
        except:
            detail_data = {}
            episodes_data = {}
    return templates.TemplateResponse(
        request=request, 
        name="detail.html", 
        context={
            "anime": detail_data.get('data', {}).get('anime', {}),
            "more_info": detail_data.get('data', {}).get('moreInfo', {}),
            "episodes": episodes_data.get('data', {}).get('episodes', [])
        }
    )

@app.get("/watch/{episode_id}", response_class=HTMLResponse)
async def watch(request: Request, episode_id: str, ep: str = None):
    full_episode_id = episode_id
    if ep:
        full_episode_id = f"{episode_id}?ep={ep}"
    
    anime_id = episode_id.split('?')[0]
    
    servers_data = {}
    anime_info = {}
    current_ep = {}
    next_ep_id = None

    async with httpx.AsyncClient() as client:
        try:
            # 1. Get Servers
            servers_resp = await client.get(f"{API_BASE}/episode/servers?animeEpisodeId={full_episode_id}")
            if servers_resp.status_code == 200:
                servers_data = servers_resp.json().get('data', {})
            
            # 2. Get Episode Info (for title and next episode)
            episodes_resp = await client.get(f"{API_BASE}/anime/{anime_id}/episodes")
            if episodes_resp.status_code == 200:
                episodes_data = episodes_resp.json().get('data', {})
                if episodes_data and 'episodes' in episodes_data:
                    ep_list = episodes_data['episodes']
                    for i, ep_obj in enumerate(ep_list):
                        if ep_obj.get('episodeId') == full_episode_id:
                            current_ep = ep_obj
                            if i + 1 < len(ep_list):
                                next_ep_id = ep_list[i+1].get('episodeId')
                            break
            
            # 3. Get Anime Info (for series title)
            detail_resp = await client.get(f"{API_BASE}/anime/{anime_id}")
            if detail_resp.status_code == 200:
                anime_info = detail_resp.json().get('data', {}).get('anime', {}).get('info', {})

        except Exception as e:
            print(f"Watch Route Error: {e}")
            
    return templates.TemplateResponse(
        request=request, 
        name="watch.html", 
        context={
            "episode_id": full_episode_id,
            "servers": servers_data,
            "anime": anime_info,
            "current_ep": current_ep,
            "next_ep_id": next_ep_id
        }
    )

@app.get("/api/source")
async def get_source(episode_id: str, server: str = "vidstreaming", category: str = "sub"):
    async with httpx.AsyncClient() as client:
        try:
            url = f"{API_BASE}/episode/sources?animeEpisodeId={episode_id}&server={server}&category={category}"
            resp = await client.get(url)
            return resp.json()
        except:
            return {}

@app.get("/azlist/{sort_option}", response_class=HTMLResponse)
async def azlist(request: Request, sort_option: str, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/azlist/{sort_option}?page={page}")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="azlist.html", 
        context={"data": data, "sort_option": sort_option, "page": page}
    )

@app.get("/schedule", response_class=HTMLResponse)
async def schedule(request: Request, date: str = None):
    if not date:
        date = dt.today().strftime("%Y-%m-%d")
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/schedule?date={date}")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="schedule.html", 
        context={"data": data, "date": date}
    )

@app.get("/genre/{name}", response_class=HTMLResponse)
async def genre(request: Request, name: str, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/genre/{name}?page={page}")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="genre.html", 
        context={"data": data, "genre": name, "page": page}
    )

# --- PROXY ENDPOINTS ---

@app.get("/proxy/m3u8")
async def proxy_m3u8(url: str, referer: str = None):
    if not url: return Response(status_code=400)
    
    clean_url = unquote(url)
    headers = get_proxy_headers(referer)

    async with httpx.AsyncClient(verify=False, follow_redirects=True) as client:
        try:
            resp = await client.get(clean_url, headers=headers)
            if resp.status_code != 200:
                # print(f"Proxy M3U8 Error {resp.status_code}: {clean_url}")
                return Response(status_code=resp.status_code)

            content = resp.text
            base_url = str(resp.url)
            
            def resolve_url(relative_url):
                return urljoin(base_url, relative_url)

            # Rewrite Key URIs
            def replace_key(match):
                original_key_url = match.group(1)
                full_key_url = resolve_url(original_key_url)
                encoded_key = quote(full_key_url)
                proxy_url = f'/proxy/key?url={encoded_key}'
                if referer:
                    proxy_url += f'&referer={quote(referer)}'
                return f'URI="{proxy_url}"'
            
            content = re.sub(r'URI="([^"]+)"', replace_key, content)
            
            # Rewrite Segment URLs
            new_lines = []
            for line in content.splitlines():
                stripped = line.strip()
                if not stripped:
                    continue
                if stripped.startswith('#'):
                    new_lines.append(line)
                else:
                    full_segment_url = resolve_url(stripped)
                    encoded_segment = quote(full_segment_url)
                    
                    if '.m3u8' in full_segment_url or 'm3u8' in full_segment_url.split('?')[0]:
                         proxy_url = f"/proxy/m3u8?url={encoded_segment}"
                    else:
                         proxy_url = f"/proxy/segment?url={encoded_segment}"
                    
                    if referer:
                        proxy_url += f"&referer={quote(referer)}"
                    new_lines.append(proxy_url)
            
            modified_content = "\n".join(new_lines)
            return Response(content=modified_content, media_type="application/vnd.apple.mpegurl")
            
        except Exception as e:
            print(f"Proxy M3U8 Exception: {e}")
            return Response(status_code=500, content=str(e))

@app.get("/proxy/segment")
async def proxy_segment(url: str, referer: str = None):
    if not url: return Response(status_code=400)
    
    clean_url = unquote(url)
    headers = get_proxy_headers(referer)
    
    async def iter_file():
        async with httpx.AsyncClient(verify=False, follow_redirects=True) as client:
            try:
                async with client.stream("GET", clean_url, headers=headers) as resp:
                    async for chunk in resp.aiter_bytes():
                        yield chunk
            except Exception as e:
                pass
                # print(f"Proxy Segment Exception: {e}")

    return StreamingResponse(iter_file(), media_type="video/mp2t")

@app.get("/proxy/key")
async def proxy_key(url: str, referer: str = None):
    if not url: return Response(status_code=400)
    clean_url = unquote(url)
    headers = get_proxy_headers(referer)

    async with httpx.AsyncClient(verify=False, follow_redirects=True) as client:
        try:
            resp = await client.get(clean_url, headers=headers)
            return Response(content=resp.content, media_type="application/octet-stream")
        except:
            return Response(status_code=500)

@app.get("/proxy/subtitle")
async def proxy_subtitle(url: str, referer: str = None):
    if not url: return Response(status_code=400)
    clean_url = unquote(url)
    headers = get_proxy_headers(referer)

    async with httpx.AsyncClient(verify=False, follow_redirects=True) as client:
        try:
            resp = await client.get(clean_url, headers=headers)
            return Response(content=resp.content, media_type="text/vtt")
        except:
            return Response(status_code=500)
