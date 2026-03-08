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

API_BASE = "https://aniverseaniwatch.vercel.app/api/v2/hianime"
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

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/home")
            data = resp.json()
            
            # Deduplicate top airing animes
            if data and "data" in data and "topAiringAnimes" in data["data"]:
                seen = set()
                deduped = []
                for anime in data["data"]["topAiringAnimes"]:
                    if anime["id"] not in seen:
                        seen.add(anime["id"])
                        deduped.append(anime)
                data["data"]["topAiringAnimes"] = deduped
        except:
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
            resp = await client.get(f"{API_BASE}/search/suggestion?q={q}")
            return resp.json()
        except:
            return {"suggestions": []}


@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = "", genres: str = None, page: int = 1):
    all_genres_list = [
        "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
        "Fantasy", "Game", "Harem", "Historical", "Horror", "Isekai", "Josei", "Kids", 
        "Magic", "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
        "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
        "Shounen", "Slice of Life", "Space", "Sports", "Super Power", "Supernatural", 
        "Thriller", "Vampire", "Yaoi", "Yuri", "Shoujo Ai", "Shounen Ai"
    ]
    all_genres = {g.lower().replace(" ", "-"): g for g in all_genres_list}
    
    # genres will come in as 'action,slice-of-life'
    selected_genres = [g.strip().lower() for g in genres.split(',')] if genres else []
    
    data = {}
    async with httpx.AsyncClient() as client:
        try:
            url = f"{API_BASE}/search?page={page}"
            
            # Use query or fallback to empty string (which we found doesn't work well)
            # Actually we can check if q exists
            if q:
                url += f"&q={q}"
            else:
                url += "&q="  # Or "a" if empty doesn't work, but let's try empty string with Hianime

            if genres:
                url += f"&genres={genres}"

            resp = await client.get(url)
            
            if resp.status_code == 200:
                data = resp.json()
            elif resp.status_code == 400 and not q:
                # Fallback if empty query is rejected
                fallback_url = f"{API_BASE}/search?page={page}&q=a"
                if genres:
                    fallback_url += f"&genres={genres}"
                resp_fallback = await client.get(fallback_url)
                if resp_fallback.status_code == 200:
                    data = resp_fallback.json()
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
            "all_genres": all_genres,
            "selected_genres": selected_genres
        }
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
            "anime_id_from_url": anime_id,  # Guaranteed to exist
            "servers": servers_data,
            "anime": anime_info,
            "current_ep": current_ep,
            "next_ep_id": next_ep_id, 
            "episodes": episodes_data.get("episodes", [])
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

@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, genres: str = None, page: int = 1):
    all_genres = [
        "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
        "Fantasy", "Game", "Harem", "Historical", "Horror", "Josei", "Kids", "Magic",
        "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
        "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
        "Shoujo Ai", "Shounen", "Shounen Ai", "Slice of Life", "Space", "Sports",
        "Super Power", "Supernatural", "Thriller", "Vampire", "Yaoi", "Yuri"
    ]
    
    selected_genres = [g.strip() for g in genres.split(',') if g.strip()] if genres else []
    
    async with httpx.AsyncClient() as client:
        try:
            # Construct API URL
            # If genres are selected, use them in search
            # If no genres and no search query, we might want to default to something or just show empty/latest
            
            # The user suggested: f"{API_BASE}/search?genres={genres}&page={page}"
            # We'll use q="" if no query is present, but here we don't have a 'q' param in the route.
            # Assuming the API supports genres param directly on search endpoint.
            
            api_url = f"{API_BASE}/search?page={page}"
            if genres:
                api_url += f"&genres={genres}"
            else:
                # If no genres, maybe default to empty search or just list generic results
                api_url += "&q=" 
                
            resp = await client.get(api_url)
            data = resp.json()
        except:
            data = {}
            
    return templates.TemplateResponse(
        request=request,
        name="browse.html",
        context={
            "data": data,
            "all_genres": all_genres,
            "selected_genres": selected_genres
        }
    )


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
            resp = await client.get(f"{MANGA_API_BASE}/info?id={manga_id}")
            if resp.status_code == 200:
                manga_info = resp.json()
                if "image" in manga_info:
                    manga_info["image"] = fix_cover(manga_info["image"])
        except Exception as e:
            print(f"Manga Detail Error: {e}")

    return templates.TemplateResponse(
        request=request,
        name="manga_detail.html",
        context={
            "manga": manga_info,
            "chapters": manga_info.get('chapters', []),
            "has_english": len(manga_info.get('chapters', [])) > 0,
            "proxy_base": MANGA_PROXY
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
            read_resp = await client.get(f"{MANGA_API_BASE}/read?chapterId={chapter_id}")
            if read_resp.status_code == 200:
                pages = read_resp.json()
                for page in pages:
                    if "img" in page:
                        # Consumet pages usually don't need proxy if we use no-referrer
                        # Just ensure domain is correct if it's mangadex
                        page["img"] = page["img"].replace("https://mangadex.org", "https://uploads.mangadex.org")
                
            # Get info for navigation
            info_resp = await client.get(f"{MANGA_API_BASE}/info?id={manga_id}")
            if info_resp.status_code == 200:
                manga_info = info_resp.json()
                chapters = manga_info.get('chapters', [])
                
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
