import re
import sys

with open('app/main.py', 'r') as f:
    content = f.read()

# The anime routes block
NEW_ANIME_ROUTES = """# --- ANIME ROUTES ---

import httpx

NEW_API_BASE = "http://localhost:8000"

def map_anilist_list(items):
    mapped = []
    for item in items:
        mapped.append({
            "id": item["id"],
            "name": item["title"].get("english") or item["title"].get("romaji"),
            "poster": item["coverImage"]["large"],
            "rank": "?"
        })
    return mapped

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            popular = await client.get(f"{NEW_API_BASE}/anime/popular?per_page=12", timeout=10)
            trending = await client.get(f"{NEW_API_BASE}/anime/trending?per_page=12", timeout=10)
            
            data = {
                "data": {
                    "spotlightAnimes": map_anilist_list(popular.json()[:6]),
                    "trendingAnimes": map_anilist_list(trending.json()),
                    "topAiringAnimes": map_anilist_list(popular.json())
                }
            }
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
                suggestions = [{"id": item["id"], "name": item["title"].get("english") or item["title"].get("romaji"), "poster": item["coverImage"]["large"]} for item in data[:5]]
                return {"suggestions": suggestions}
            return {"suggestions": []}
        except:
            return {"suggestions": []}

@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = "", genres: str = None, page: int = 1):
    # Simplified search using Anilist via the new API
    data = {}
    async with httpx.AsyncClient() as client:
        try:
            if q:
                resp = await client.get(f"{NEW_API_BASE}/anime/search/{quote(q)}")
                res_json = resp.json()
                if isinstance(res_json, list):
                    data = {
                        "data": {
                            "animes": map_anilist_list(res_json),
                            "totalPages": 1,
                            "hasNextPage": False,
                            "currentPage": 1
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
            "all_genres": {} # Disable genre filter for now since anilist API doesn't expose it here
        }
    )

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
                    "type": "TV"
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
            "servers": [{"serverName": "Auto", "category": "sub"}],
            "episodes": episodes
        }
    )

@app.get("/api/source")
async def get_source(episode_id: str, server: str = "Auto", category: str = "sub"):
    try:
        anilist_id, ep_num = episode_id.split("/")
        url = f"{NEW_API_BASE}/anime/resolve/{anilist_id}/{ep_num}"
        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=30)
            data = resp.json()
            
            sources = []
            for stream in data.get("streams", []):
                sources.append({
                    "url": stream["url"],
                    "isM3U8": "m3u8" in stream["url"],
                    "quality": stream.get("quality", "auto")
                })
                
            return {
                "data": {
                    "sources": sources,
                    "subtitles": data.get("subtitles", [])
                }
            }
    except Exception as e:
        print("Source Error:", e)
        return {}

# Stub out old unused routes so they don't 404
@app.get("/azlist/{sort_option}", response_class=HTMLResponse)
async def azlist(request: Request, sort_option: str, page: int = 1):
    return templates.TemplateResponse(request=request, name="azlist.html", context={"data": {}})

@app.get("/schedule", response_class=HTMLResponse)
async def schedule(request: Request, date: str = dt.today().strftime('%Y-%m-%d')):
    return templates.TemplateResponse(request=request, name="schedule.html", context={"data": {}, "date": date})

@app.get("/genre/{name}", response_class=HTMLResponse)
async def genre(request: Request, name: str, page: int = 1):
    return templates.TemplateResponse(request=request, name="genre.html", context={"data": {}})

@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, page: int = 1):
    return templates.TemplateResponse(request=request, name="browse.html", context={"data": {}})

"""

pattern = re.compile(r'# --- ANIME ROUTES ---.*?# --- MANGA ROUTES ---', re.DOTALL)
new_content = pattern.sub(NEW_ANIME_ROUTES + "\n# --- MANGA ROUTES ---", content)

with open('app/main.py', 'w') as f:
    f.write(new_content)

print("Rewrote app/main.py")
