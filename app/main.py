import sys
import os
import re
from urllib.parse import urljoin, quote, unquote
from datetime import date as dt
import asyncio

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

API_BASE = "https://aniverseaniwatch.onrender.com/"
MANGA_API_BASE = "https://consumet-swart-nine.vercel.app/manga/mangadex"
MANGA_PROXY = "https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url="
DEFAULT_REFERER = "https://hianime.to/"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

def get_proxy_headers(referer: str = None):
    return {
        "User-Agent": USER_AGENT,
        "Referer": referer if referer else DEFAULT_REFERER,
        "Origin": referer if referer else DEFAULT_REFERER
    }

def fix_cover(url: str):
    import sys
    if not url:
        return url
    
    # Only fix the domain
    fixed_url = url.replace("https://mangadex.org/covers", "https://uploads.mangadex.org/covers")
    
    # Add logging as requested
    print(f"fix_cover INPUT: {url} | OUTPUT: {fixed_url}")
    sys.stdout.flush()
    
    # Return direct URL without prepending MANGA_PROXY and without quote()
    return fixed_url

# --- ANIME ROUTES ---

import httpx

NEW_API_BASE = "http://localhost:8001"

def map_anilist_list(items):
    mapped = []
    for idx, item in enumerate(items):
        mapped.append({
            "id": item.get("id"),
            "name": item.get("title", {}).get("english") or item.get("title", {}).get("romaji"),
            "poster": item.get("coverImage", {}).get("large"),
            "rank": str(idx + 1)
        })
    return mapped

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            popular = await client.get(f"{NEW_API_BASE}/anime/popular?per_page=12", timeout=10)
            trending = await client.get(f"{NEW_API_BASE}/anime/trending?per_page=12", timeout=10)
            latest = await client.get(f"{NEW_API_BASE}/anime/latest?per_page=12", timeout=10)
            upcoming = await client.get(f"{NEW_API_BASE}/anime/upcoming?per_page=12", timeout=10)
            
            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                ep_count = "?"
                # We specifically injected exact_latest_episode from the AiringSchedule backend
                if item.get("exact_latest_episode"):
                    ep_count = str(item["exact_latest_episode"])
                elif item.get("nextAiringEpisode"):
                    ep = item["nextAiringEpisode"]["episode"]
                    ep_count = str(ep - 1) if ep > 1 else "1"
                elif item.get("episodes"):
                    ep_count = str(item["episodes"])
                    
                item["episodes"] = {"sub": ep_count}

            data = {
                "data": {
                    "spotlightAnimes": map_anilist_list(popular.json()[:6]),
                    "trendingAnimes": map_anilist_list(trending.json()),
                    "topAiringAnimes": map_anilist_list(popular.json()),
                    "latestEpisodeAnimes": map_anilist_list(latest_list),
                    "topUpcomingAnimes": map_anilist_list(upcoming.json())
                }
            }
            # Add sub badges back for latest
            for idx, item in enumerate(latest_list):
                if idx < len(data["data"]["latestEpisodeAnimes"]):
                    data["data"]["latestEpisodeAnimes"][idx]["episodes"] = item.get("episodes")
                    
        except Exception as e:
            print("Home Error:", e)
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="home.html", 
        context={"data": data}
    )

@app.get("/history", response_class=HTMLResponse)
async def history(request: Request):
    return templates.TemplateResponse(
        request=request, 
        name="history.html", 
        context={}
    )

@app.get("/search/suggestion")
async def search_suggestion(q: str):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/search/{quote(q)}")
            data = resp.json()
            if isinstance(data, list):
                suggestions = [{"id": item["id"], "name": item["title"].get("english") or item["title"].get("romaji"), "poster": item["coverImage"]["large"], "moreInfo": ["Anime"]} for item in data[:5]]
                return {"data": {"suggestions": suggestions}}
            return {"data": {"suggestions": []}}
        except:
            return {"data": {"suggestions": []}}

@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = "", genres: str = None, page: int = 1):
    all_genres_list = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", 
        "Horror", "Mahou Shoujo", "Mecha", "Music", "Mystery", 
        "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", 
        "Supernatural", "Thriller"
    ]
    all_genres = {g.lower().replace(" ", "-"): g for g in all_genres_list}
    
    selected_genres = [g.strip().lower() for g in genres.split(',')] if genres else []
    
    # Map selected slugs back to Anilist Proper Case names
    mapped_genres = []
    for g in selected_genres:
        if g in all_genres:
            mapped_genres.append(all_genres[g])
            
    query = '''
    query ($search: String, $genres: [String], $page: Int, $sort: [MediaSort]) {
      Page (page: $page, perPage: 24) {
        pageInfo {
          total
          currentPage
          lastPage
          hasNextPage
          perPage
        }
        media (type: ANIME, search: $search, genre_in: $genres, sort: $sort) {
          id
          title { romaji english }
          coverImage { large }
        }
      }
    }
    '''
    
    variables = {"page": page}
    if q:
        variables["search"] = q
        variables["sort"] = ["SEARCH_MATCH", "POPULARITY_DESC"]
    else:
        variables["sort"] = ["TRENDING_DESC"]
        
    if mapped_genres:
        variables["genres"] = mapped_genres
        
    data = {}
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
            res_data = resp.json().get("data", {}).get("Page", {})
            if res_data:
                data = {
                    "data": {
                        "animes": map_anilist_list(res_data.get("media", [])),
                        "totalPages": res_data.get("pageInfo", {}).get("lastPage", 1),
                        "hasNextPage": res_data.get("pageInfo", {}).get("hasNextPage", False),
                        "currentPage": res_data.get("pageInfo", {}).get("currentPage", 1)
                    }
                }
        except Exception as e:
            print("Search Error:", e)
            data = {}

    return templates.TemplateResponse(
        request=request, 
        name="search.html", 
        context={
            "data": data, 
            "query": q, 
            "page": page,
            "genres": genres or "",
            "selected_genres": selected_genres,
            "all_genres": all_genres
        }
    )

@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, page: int = 1, genres: str = None):
    # Just redirect browse to search without query, it does the exact same thing but correctly filters
    from fastapi.responses import RedirectResponse
    url = f"/search?page={page}"
    if genres:
        url += f"&genres={genres}"
    return RedirectResponse(url)

@app.get("/anime/{anime_id}", response_class=HTMLResponse)

async def anime_detail(request: Request, anime_id: str):
    query = '''
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        title { romaji english }
        description
        coverImage { large }
        episodes
        genres
        averageScore
        status
      }
    }
    '''
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post("https://graphql.anilist.co", json={'query': query, 'variables': {'id': int(anime_id)}})
            media = resp.json().get("data", {}).get("Media", {})
            if not media:
                raise Exception("Not found")
            
            title = media["title"].get("english") or media["title"].get("romaji")
            ep_count = media.get("episodes") or 12
            
            anime_info = {
                "name": title,
                "poster": media["coverImage"]["large"],
                "description": media.get("description", "No description available."),
                "stats": {
                    "rating": f"{media.get('averageScore', 'N/A')}/100",
                    "quality": "HD",
                    "episodes": {"sub": ep_count, "dub": 0},
                    "type": "TV",
                    "status": media.get("status", "FINISHED")
                }
            }
            
            episodes = []
            for i in range(1, ep_count + 1):
                episodes.append({
                    "episodeId": f"{anime_id}/{i}",
                    "number": i,
                    "title": f"Episode {i}",
                    "isFiller": False
                })
                
            return templates.TemplateResponse(
                request=request, 
                name="detail.html", 
                context={
                    "anime": {"info": anime_info, "moreInfo": {"genres": media.get("genres", [])}}, 
                    "episodes": episodes
                }
            )
        except Exception as e:
            print("Detail Error:", e)
            return HTMLResponse("Anime not found or error occurred", status_code=404)

@app.get("/watch/{anime_id}/{ep_num}", response_class=HTMLResponse)
async def watch_episode(request: Request, anime_id: str, ep_num: int):
    # This replaces the old /watch/{episode_id} route
    episode_id = f"{anime_id}/{ep_num}"
    
    query = '''
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        title { romaji english }
        coverImage { large }
        episodes
        status
      }
    }
    '''
    anime_info = {"name": f"Anime {anime_id}", "poster": ""}
    episodes = []
    
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post("https://graphql.anilist.co", json={'query': query, 'variables': {'id': int(anime_id)}})
            media = resp.json().get("data", {}).get("Media", {})
            if media:
                anime_info["name"] = media["title"].get("english") or media["title"].get("romaji")
                anime_info["poster"] = media["coverImage"]["large"]
                anime_info["status"] = media.get("status")
                
                if anime_info["status"] == "NOT_YET_RELEASED":
                    return HTMLResponse("<div style='color:white; text-align:center; padding:50px; font-family:sans-serif;'><h2>This Anime Hasn't been release yet</h2><a href='/' style='color:#e50914;'>Go Home</a></div>", status_code=403)
                    
                ep_count = media.get("episodes") or 12
                for i in range(1, ep_count + 1):
                    episodes.append({
                        "episodeId": f"{anime_id}/{i}",
                        "number": i,
                        "title": f"Episode {i}"
                    })
        except:
            pass

    next_ep_id = f"{anime_id}/{ep_num + 1}" if any(e["number"] == ep_num + 1 for e in episodes) else None

    return templates.TemplateResponse(
        request=request, 
        name="watch.html", 
        context={
            "episode_id": episode_id,
            "anime_id_from_url": anime_id,
            "anime": anime_info,
            "current_ep": {"number": ep_num, "title": f"Episode {ep_num}"},
            "next_ep_id": next_ep_id,
            "servers": {
                "sub": [{"serverName": "Auto", "category": "sub"}],
                "dub": [{"serverName": "Auto", "category": "dub"}]
            },
            "episodes": episodes
        }
    )

@app.get("/api/source")
async def get_source(episode_id: str, server: str = "Auto", category: str = "sub"):
    try:
        anilist_id, ep_num = episode_id.split("/")
        url = f"{NEW_API_BASE}/anime/resolve/{anilist_id}/{ep_num}?category={category}"
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=30)
            data = resp.json()
            
            sources = []
            for stream in data.get("streams", []):
                # Always proxy the master m3u8 to bypass IP-locked streams like premilkyway.com
                abs_url = stream["url"]
                referer = data.get("headers", {}).get("Referer", "https://cloudnestra.com/")
                
                # Fix Referer specifically for StreamHG / premilkyway streams
                if "premilkyway.com" in abs_url:
                    referer = "https://otakuhg.site/"
                elif "vibeplayer.site" in abs_url:
                    referer = "https://vibeplayer.site/"
                elif "cloudatacdn" in abs_url or "dood" in abs_url:
                    referer = "https://myvidplay.com/"
                    
                # Do NOT proxy premilkyway.com streams because they use tokenized IPs/Cookies
                if "premilkyway.com" in abs_url:
                    proxy_url = abs_url
                elif "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    # It's an mp4 like Doodstream, proxy it using our stream endpoint!
                    proxy_url = f"/proxy/stream?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"

                    
                sources.append({
                    "url": proxy_url,
                    "isM3U8": "m3u8" in abs_url,
                    "quality": stream.get("quality", "auto"),
                    "serverName": stream.get("server", "Auto")
                })
                
            return {
                "data": {
                    "sources": sources,
                    "subtitles": data.get("subtitles", []),
                    "headers": data.get("headers", {})
                }
            }
    except Exception as e:
        print("Source Error:", e)
        return {}

# Rewritten routes
@app.get("/azlist/{sort_option}", response_class=HTMLResponse)
async def azlist(request: Request, sort_option: str, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/browse?sort=TITLE_ROMAJI&page={page}&per_page=24")
            data = {"data": {"animes": map_anilist_list(resp.json()), "totalPages": 10, "hasNextPage": True, "currentPage": page}}
        except:
            data = {}
    return templates.TemplateResponse(request=request, name="azlist.html", context={"data": data})

@app.get("/schedule", response_class=HTMLResponse)
async def schedule(request: Request, date: str = dt.today().strftime('%Y-%m-%d')):
    # Anilist upcoming proxy for schedule
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/upcoming?page=1&per_page=24")
            data = {"data": {"scheduledAnimes": map_anilist_list(resp.json())}}
        except:
            data = {}
    return templates.TemplateResponse(request=request, name="schedule.html", context={"data": data, "date": date})

@app.get("/genre/{name}", response_class=HTMLResponse)
async def genre(request: Request, name: str, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            # Capitalize properly for Anilist (e.g. Action)
            resp = await client.get(f"{NEW_API_BASE}/anime/genre/{name.capitalize()}?page={page}&per_page=24")
            data = {"data": {"animes": map_anilist_list(resp.json()), "totalPages": 10, "hasNextPage": True, "currentPage": page, "genreName": name}}
        except:
            data = {}
    return templates.TemplateResponse(request=request, name="genre.html", context={"data": data})




# --- MANGA ROUTES ---

@app.get("/manga", response_class=HTMLResponse)
async def manga_home(request: Request):
    popular_data = []
    latest_data = []
    recent_data = []
    
    async with httpx.AsyncClient() as client:
        try:
            # Featured / Popular
            pop_resp = await client.get(f"{MANGA_API_BASE}/popular")
            if pop_resp.status_code == 200:
                popular_data = pop_resp.json().get('results', [])
                for item in popular_data:
                    if "image" in item:
                        item["image"] = fix_cover(item["image"])

            # Latest Updates
            latest_resp = await client.get(f"{MANGA_API_BASE}/latest")
            if latest_resp.status_code == 200:
                latest_data = latest_resp.json().get('results', [])
                for item in latest_data:
                    if "image" in item:
                        item["image"] = fix_cover(item["image"])
                
            # Recent Additions
            recent_resp = await client.get(f"{MANGA_API_BASE}/recent")
            if recent_resp.status_code == 200:
                recent_data = recent_resp.json().get('results', [])
                for item in recent_data:
                    if "image" in item:
                        item["image"] = fix_cover(item["image"])

        except Exception as e:
            print(f"Manga Home Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_home.html",
        context={
            "popular": popular_data,
            "latest": latest_data,
            "recent": recent_data,
            "proxy_base": MANGA_PROXY
        }
    )

@app.get("/manga/search/suggestion")
async def manga_search_suggestion(q: str):
    async with httpx.AsyncClient() as client:
        try:
            url = f"{MANGA_API_BASE}/{q}"
            resp = await client.get(url)
            if resp.status_code == 200:
                # We can just return the raw results from Consumet
                data = resp.json()
                results = data.get('results', [])
                for item in results:
                    if "image" in item:
                        item["image"] = fix_cover(item["image"])
                return data
        except:
            return {"results": []}
    return {"results": []}

@app.get("/manga/proxy")
async def basic_manga_proxy(url: str):
    from fastapi.responses import RedirectResponse
    # Since proxy is broken, just redirect to the fixed URL
    fixed_url = url.replace("https://mangadex.org", "https://uploads.mangadex.org")
    return RedirectResponse(fixed_url)

@app.get("/manga/search", response_class=HTMLResponse)
async def manga_search(request: Request, q: str = "", page: int = 1):
    results = []
    async with httpx.AsyncClient() as client:
        try:
            url = f"{MANGA_API_BASE}/{q}?page={page}"
            resp = await client.get(url)
            if resp.status_code == 200:
                results = resp.json().get('results', [])
                for item in results:
                    if "image" in item:
                        item["image"] = fix_cover(item["image"])
        except Exception as e:
            print(f"Manga Search Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_search.html",
        context={
            "results": results,
            "query": q,
            "page": page,
            "proxy_base": MANGA_PROXY
        }
    )

@app.get("/manga/{manga_id}", response_class=HTMLResponse)
async def manga_detail(request: Request, manga_id: str):
    manga_info = {}
    async with httpx.AsyncClient() as client:
        try:
            url = f"{MANGA_API_BASE}/info/{manga_id.strip('/')}"
            print(f"CALLING: {url}")
            import sys; sys.stdout.flush()
            resp = await client.get(url, timeout=30)
            print(f"STATUS: {resp.status_code}")
            print(f"BODY: {resp.text[:200]}")
            sys.stdout.flush()
            if resp.status_code == 200:
                print(f"Detail API Keys: {list(resp.json().keys())}")
                sys.stdout.flush()
                manga_info = resp.json()
                if not manga_info.get("title"):
                    alt_titles = manga_info.get("altTitles", [])
                    fallback = "Unknown Title"
                    for alt in alt_titles:
                        if isinstance(alt, dict):
                            if "en" in alt:
                                fallback = alt["en"]
                                break
                            elif alt:
                                fallback = list(alt.values())[0]
                    manga_info["title"] = fallback

                if "image" in manga_info:
                    manga_info["image"] = fix_cover(manga_info["image"])
                
                # Sanitize description
                desc = manga_info.get("description")
                if isinstance(desc, dict):
                    manga_info["description"] = desc.get("en", list(desc.values())[0] if desc else "No description available.")
                
                # Ensure fields exist for template
                manga_info["authors"] = manga_info.get("authors") or []
                manga_info["genres"] = (manga_info.get("genres") or []) + (manga_info.get("themes") or [])
                manga_info["rating"] = manga_info.get("rating") or "N/A"
        except Exception as e:
            print(f"Manga Detail ERROR: {str(e)}")
            import sys; sys.stdout.flush()

    return templates.TemplateResponse(
        request=request,
        name="manga_detail.html",
        context={
            "manga": manga_info,
            "chapters": manga_info.get('chapters', []),
            "has_english": len(manga_info.get('chapters', [])) > 0,
            "proxy_base": MANGA_PROXY,
            "error": not bool(manga_info.get('title'))
        }
    )

@app.get("/manga/read/{manga_id}/{chapter_id}", response_class=HTMLResponse)
async def manga_read(request: Request, manga_id: str, chapter_id: str):
    pages = []
    manga_info = {}
    current_chapter = None
    next_chapter = None
    prev_chapter = None
    
    async with httpx.AsyncClient() as client:
        try:
            # Get pages
            read_resp = await client.get(f"{MANGA_API_BASE}/read/{chapter_id.strip('/')}", timeout=30)
            if read_resp.status_code == 200:
                pages = read_resp.json()
                for page in pages:
                    if page.get("img"):
                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page['img'], safe='')}"
                
            # Get info for navigation
            info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=30)
            if info_resp.status_code == 200:
                manga_info = info_resp.json()
                
                if not manga_info.get("title"):
                    alt_titles = manga_info.get("altTitles", [])
                    fallback = "Unknown Title"
                    for alt in alt_titles:
                        if isinstance(alt, dict):
                            if "en" in alt:
                                fallback = alt["en"]
                                break
                            elif alt:
                                fallback = list(alt.values())[0]
                    manga_info["title"] = fallback
                    
                chapters = manga_info.get('chapters', [])
                print(f"Read Info API Status: {info_resp.status_code}, Chapters found: {len(chapters)}")
                
                # Consumet returns chapters usually in descending order
                for i, ch in enumerate(chapters):
                    if ch.get('id') == chapter_id:
                        current_chapter = ch
                        if i > 0:
                            next_chapter = chapters[i-1].get('id')  # Newer chapter is before it in desc order
                        if i < len(chapters) - 1:
                            prev_chapter = chapters[i+1].get('id')  # Older chapter is after it
                        break

        except Exception as e:
            print(f"Manga Read Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_read.html",
        context={
            "manga_id": manga_id,
            "chapter_id": chapter_id,
            "pages": pages,
            "manga_info": manga_info,
            "chapter_info": current_chapter or {},
            "next_chapter": next_chapter,
            "prev_chapter": prev_chapter,
            "proxy_base": MANGA_PROXY
        }
    )


@app.api_route("/proxy/stream", methods=["GET", "HEAD"])
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

        if request.method == "HEAD":
            return Response(content="", status_code=status_code, headers=resp_headers, media_type=head_resp.headers.get("Content-Type", "video/mp4"))

        return StreamingResponse(
            stream_generator(),
            status_code=status_code,
            headers=resp_headers,
            media_type=head_resp.headers.get("Content-Type", "video/mp4")
        )
    except Exception as e:
        print(f"Proxy Stream Error: {e}")
        return Response(status_code=500, content="Proxy Stream Error")

@app.get("/proxy/m3u8")
async def proxy_m3u8(url: str, referer: str = None):
    headers = {"User-Agent": USER_AGENT}
    if referer:
        headers["Referer"] = referer
        headers["Origin"] = referer.rstrip("/")
    
    async with httpx.AsyncClient(timeout=8.0) as client:
        try:
            resp = await client.get(url, headers=headers)
            content = resp.text
            
            lines = content.split('\n')
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
            
            return Response(content='\n'.join(rewritten_lines), media_type="application/vnd.apple.mpegurl")
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
        async with httpx.AsyncClient(timeout=8.0) as client:
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
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                async with client.stream("GET", url, headers=headers) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                print(f"Proxy Subtitle Error: {e}")
                yield b"Proxy Error"
    
    return StreamingResponse(stream_subtitle(), media_type="text/vtt")
