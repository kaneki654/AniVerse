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
MANGA_API_BASE = "https://api.mangadex.org"
DEFAULT_REFERER = "https://hianime.to/"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_proxy_headers(referer: str = None):
    return {
        "User-Agent": USER_AGENT,
        "Referer": referer if referer else DEFAULT_REFERER,
        "Origin": referer if referer else DEFAULT_REFERER
    }

# --- ANIME ROUTES ---

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

# --- MANGA ROUTES ---

def process_manga_list(data):
    """Helper to process MangaDex API response into a cleaner format."""
    manga_list = []
    for item in data:
        manga_id = item.get('id')
        attrs = item.get('attributes', {})
        relationships = item.get('relationships', [])
        
        # Get title (prioritize en)
        title = attrs.get('title', {}).get('en') or list(attrs.get('title', {}).values())[0]
        
        # Get cover filename
        cover_filename = None
        for rel in relationships:
            if rel.get('type') == 'cover_art':
                cover_filename = rel.get('attributes', {}).get('fileName')
                break
        
        cover_url = f"https://uploads.mangadex.org/covers/{manga_id}/{cover_filename}.256.jpg" if cover_filename else "/static/placeholder.jpg"
        
        manga_list.append({
            "id": manga_id,
            "title": title,
            "cover": cover_url,
            "desc": attrs.get('description', {}).get('en', '')
        })
    return manga_list

@app.get("/manga", response_class=HTMLResponse)
async def manga_home(request: Request):
    async with httpx.AsyncClient() as client:
        popular_data = []
        latest_data = []
        tags = []
        try:
            # Popular Manga
            pop_resp = await client.get(f"{MANGA_API_BASE}/manga?limit=20&order[followedCount]=desc&includes[]=cover_art&contentRating[]=safe")
            if pop_resp.status_code == 200:
                popular_data = process_manga_list(pop_resp.json().get('data', []))

            # Latest Updates
            latest_resp = await client.get(f"{MANGA_API_BASE}/manga?limit=20&order[latestUploadedChapter]=desc&includes[]=cover_art&contentRating[]=safe")
            if latest_resp.status_code == 200:
                latest_data = process_manga_list(latest_resp.json().get('data', []))
                
            # Tags
            tags_resp = await client.get(f"{MANGA_API_BASE}/manga/tag")
            if tags_resp.status_code == 200:
                tags = sorted(tags_resp.json().get('data', []), key=lambda x: x['attributes']['name']['en'])

        except Exception as e:
            print(f"Manga Home Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_home.html",
        context={
            "popular": popular_data,
            "latest": latest_data,
            "tags": tags
        }
    )

@app.get("/manga/search", response_class=HTMLResponse)
async def manga_search(request: Request, title: str = "", tag: str = None, page: int = 1):
    limit = 20
    offset = (page - 1) * limit
    async with httpx.AsyncClient() as client:
        results = []
        try:
            params = {
                "limit": limit,
                "offset": offset,
                "includes[]": "cover_art",
                "contentRating[]": "safe"
            }
            if title:
                params["title"] = title
            if tag:
                params["includedTags[]"] = tag
            
            resp = await client.get(f"{MANGA_API_BASE}/manga", params=params)
            if resp.status_code == 200:
                results = process_manga_list(resp.json().get('data', []))
        except Exception as e:
            print(f"Manga Search Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_search.html",
        context={
            "results": results,
            "query": title,
            "page": page,
            "tag": tag
        }
    )

@app.get("/manga/{manga_id}", response_class=HTMLResponse)
async def manga_detail(request: Request, manga_id: str):
    async with httpx.AsyncClient() as client:
        manga_info = {}
        chapters = []
        has_english = False
        
        try:
            # Manga Info
            resp = await client.get(f"{MANGA_API_BASE}/manga/{manga_id}?includes[]=author&includes[]=artist&includes[]=cover_art")
            if resp.status_code == 200:
                data = resp.json().get('data', {})
                attrs = data.get('attributes', {})
                rels = data.get('relationships', [])
                
                cover = next((r for r in rels if r['type'] == 'cover_art'), {})
                cover_file = cover.get('attributes', {}).get('fileName')
                cover_url = f"https://uploads.mangadex.org/covers/{manga_id}/{cover_file}" if cover_file else ""
                
                author = next((r for r in rels if r['type'] == 'author'), {})
                author_name = author.get('attributes', {}).get('name', 'Unknown')

                manga_info = {
                    "id": data.get('id'),
                    "title": attrs.get('title', {}).get('en') or list(attrs.get('title', {}).values())[0],
                    "desc": attrs.get('description', {}).get('en', ''),
                    "cover": cover_url,
                    "author": author_name,
                    "status": attrs.get('status'),
                    "year": attrs.get('year'),
                    "tags": [t['attributes']['name']['en'] for t in attrs.get('tags', [])]
                }

            # Chapters - Fetch English feed with limit 500 to get substantial history
            feed_resp = await client.get(f"{MANGA_API_BASE}/manga/{manga_id}/feed?translatedLanguage[]=en&order[chapter]=desc&limit=500&includes[]=scanlation_group")
            
            if feed_resp.status_code == 200:
                feed_data = feed_resp.json().get('data', [])
                
                processed_chapters = []
                seen_chapters = set()
                
                if feed_data:
                    has_english = True
                    for ch in feed_data:
                        attrs = ch.get('attributes', {})
                        ch_num = attrs.get('chapter')
                        
                        # Handle oneshots or nulls
                        if ch_num is None:
                            ch_num_key = "oneshot_" + ch['id'] # unique key for oneshots to show all
                        else:
                            ch_num_key = ch_num
                            
                        # Deduplication: Only take first occurrence of a chapter number
                        if ch_num_key in seen_chapters and ch_num is not None:
                            continue
                        
                        if ch_num is not None:
                            seen_chapters.add(ch_num_key)
                            
                        # Extract Group Name
                        group_name = "Unknown Group"
                        for rel in ch.get('relationships', []):
                            if rel['type'] == 'scanlation_group':
                                group_name = rel.get('attributes', {}).get('name')
                                break

                        processed_chapters.append({
                            "id": ch.get('id'),
                            "chapter": ch_num,
                            "volume": attrs.get('volume'),
                            "title": attrs.get('title'),
                            "group": group_name,
                            "date": attrs.get('publishAt', '').split('T')[0]
                        })
                    
                    chapters = processed_chapters

        except Exception as e:
            print(f"Manga Detail Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_detail.html",
        context={
            "manga": manga_info,
            "chapters": chapters,
            "has_english": has_english
        }
    )

@app.get("/manga/read/{chapter_id}", response_class=HTMLResponse)
async def manga_read(request: Request, chapter_id: str):
    pages = []
    chapter_info = {}
    next_chapter = None
    prev_chapter = None
    
    async with httpx.AsyncClient() as client:
        try:
            # 1. Get Chapter Pages (At-Home Server)
            resp = await client.get(f"{MANGA_API_BASE}/at-home/server/{chapter_id}")
            if resp.status_code == 200:
                data = resp.json()
                base_url = data.get('baseUrl')
                chapter_hash = data.get('chapter', {}).get('hash')
                filenames = data.get('chapter', {}).get('data', [])
                
                pages = [f"{base_url}/data/{chapter_hash}/{fn}" for fn in filenames]

            # 2. Get Chapter Info (to find parent manga)
            ch_resp = await client.get(f"{MANGA_API_BASE}/chapter/{chapter_id}?includes[]=manga")
            if ch_resp.status_code == 200:
                ch_data = ch_resp.json().get('data', {})
                attrs = ch_data.get('attributes', {})
                chapter_info = {
                    "title": attrs.get('title'),
                    "chapter": attrs.get('chapter'),
                    "manga_id": next((r['id'] for r in ch_data.get('relationships', []) if r['type'] == 'manga'), None)
                }
                
                # 3. Find Neighbors
                if chapter_info["manga_id"]:
                    # Fetch sparse feed for navigation
                    feed_resp = await client.get(f"{MANGA_API_BASE}/manga/{chapter_info['manga_id']}/feed?translatedLanguage[]=en&order[chapter]=asc&limit=500")
                    if feed_resp.status_code == 200:
                        all_chapters = feed_resp.json().get('data', [])
                        
                        # Filter for unique chapters to match navigation
                        unique_chapters = []
                        seen = set()
                        for ch in all_chapters:
                            num = ch['attributes']['chapter']
                            if num and num not in seen:
                                seen.add(num)
                                unique_chapters.append(ch)
                            elif num is None:
                                unique_chapters.append(ch)

                        curr_idx = -1
                        for i, ch in enumerate(unique_chapters):
                            if ch['id'] == chapter_id or (ch['attributes']['chapter'] == chapter_info['chapter'] and chapter_info['chapter'] is not None):
                                curr_idx = i
                                break
                        
                        if curr_idx != -1:
                            if curr_idx > 0:
                                prev_chapter = unique_chapters[curr_idx - 1]['id']
                            if curr_idx < len(unique_chapters) - 1:
                                next_chapter = unique_chapters[curr_idx + 1]['id']

        except Exception as e:
            print(f"Manga Read Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_read.html",
        context={
            "pages": pages,
            "info": chapter_info,
            "next_id": next_chapter,
            "prev_id": prev_chapter
        }
    )

@app.get("/manga/search/suggestion")
async def manga_search_suggestion_proxy(q: str):
    async with httpx.AsyncClient() as client:
        try:
            params = {
                "title": q,
                "limit": 6,
                "includes[]": "cover_art",
                "contentRating[]": "safe"
            }
            resp = await client.get(f"{MANGA_API_BASE}/manga", params=params)
            if resp.status_code == 200:
                raw_data = resp.json().get('data', [])
                results = []
                for item in raw_data:
                    manga_id = item.get('id')
                    attrs = item.get('attributes', {})
                    relationships = item.get('relationships', [])
                    
                    title = attrs.get('title', {}).get('en') or list(attrs.get('title', {}).values())[0]
                    
                    cover_filename = None
                    for rel in relationships:
                        if rel.get('type') == 'cover_art':
                            cover_filename = rel.get('attributes', {}).get('fileName')
                            break
                    
                    cover_url = f"https://uploads.mangadex.org/covers/{manga_id}/{cover_filename}.256.jpg" if cover_filename else "/static/placeholder.jpg"
                    
                    tags = [t['attributes']['name']['en'] for t in attrs.get('tags', [])]
                    
                    results.append({
                        "id": manga_id,
                        "title": title,
                        "cover": cover_url,
                        "status": attrs.get('status'),
                        "tags": tags
                    })
                return {"results": results}
        except Exception as e:
            print(f"Manga Suggestion Error: {e}")
            return {"results": []}

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
