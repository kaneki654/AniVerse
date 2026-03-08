import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Replace MANGA_API_BASE
content = content.replace('MANGA_API_BASE = "https://api.mangadex.org"', 
'''MANGA_API_BASE = "https://consumet-swart-nine.vercel.app/manga/mangadex"
MANGA_PROXY = "https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url="''')

# Now find the whole MANGA ROUTES section and replace it
import re

# Match from `# --- MANGA ROUTES ---` down to the end of the file or next major section.
# We'll just replace everything from `# --- MANGA ROUTES ---` to the end of the file, because we need to rewrite all manga routes and delete proxy routes.
manga_routes_pattern = re.compile(r'# --- MANGA ROUTES ---.*', re.DOTALL)

new_manga_routes = """# --- MANGA ROUTES ---

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

            # Latest Updates
            latest_resp = await client.get(f"{MANGA_API_BASE}/latest")
            if latest_resp.status_code == 200:
                latest_data = latest_resp.json().get('results', [])
                
            # Recent Additions
            recent_resp = await client.get(f"{MANGA_API_BASE}/recent")
            if recent_resp.status_code == 200:
                recent_data = recent_resp.json().get('results', [])

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

@app.get("/manga/search", response_class=HTMLResponse)
async def manga_search(request: Request, q: str = "", page: int = 1):
    results = []
    async with httpx.AsyncClient() as client:
        try:
            url = f"{MANGA_API_BASE}/{q}?page={page}"
            resp = await client.get(url)
            if resp.status_code == 200:
                results = resp.json().get('results', [])
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
"""

content = manga_routes_pattern.sub(new_manga_routes, content)

with open('app/main.py', 'w') as f:
    f.write(content)
