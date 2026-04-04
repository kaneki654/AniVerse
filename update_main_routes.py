import re

with open('app/main.py', 'r') as f:
    content = f.read()

def inject_home(content):
    new_home = """@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            popular = await client.get(f"{NEW_API_BASE}/anime/popular?per_page=12", timeout=10)
            trending = await client.get(f"{NEW_API_BASE}/anime/trending?per_page=12", timeout=10)
            latest = await client.get(f"{NEW_API_BASE}/anime/latest?per_page=12", timeout=10)
            upcoming = await client.get(f"{NEW_API_BASE}/anime/upcoming?per_page=12", timeout=10)
            
            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                item["episodes"] = {"sub": item.get("episodes") or "?"}

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
                    data["data"]["latestEpisodeAnimes"][idx]["episodes"] = {"sub": item.get("episodes") or "?"}
                    
        except Exception as e:
            print("Home Error:", e)
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="home.html", 
        context={"data": data}
    )"""
    return re.sub(r'@app\.get\("/", response_class=HTMLResponse\).*?return templates\.TemplateResponse\([^)]+\)', new_home, content, flags=re.DOTALL)

def inject_stubs(content):
    new_stubs = """# Rewritten routes
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

@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/browse?sort=TRENDING_DESC&page={page}&per_page=24")
            data = {"data": {"animes": map_anilist_list(resp.json()), "totalPages": 10, "hasNextPage": True, "currentPage": page}}
        except:
            data = {}
    return templates.TemplateResponse(request=request, name="browse.html", context={"data": data})"""
    
    # Replace the old stubs block
    pattern = r'# Stub out old unused routes so they don\'t 404.*?@app\.get\("/anime/browse", response_class=HTMLResponse\).*?return templates\.TemplateResponse\([^)]+\)'
    return re.sub(pattern, new_stubs, content, flags=re.DOTALL)

new_content = inject_stubs(inject_home(content))
with open('app/main.py', 'w') as f:
    f.write(new_content)
print("Updated main.py routes")
