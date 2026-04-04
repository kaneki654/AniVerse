with open('app/main.py', 'r') as f:
    content = f.read()

# Fix search
old_search_context = """        context={
            "data": data, 
            "query": q, 
            "page": page,
            "genres": genres or "",
            "all_genres": {} # Disable genre filter for now since anilist API doesn't expose it here
        }"""

new_search_context = """        context={
            "data": data, 
            "query": q, 
            "page": page,
            "genres": genres or "",
            "selected_genres": [g.strip().lower() for g in genres.split(',')] if genres else [],
            "all_genres": {} # Disable genre filter for now since anilist API doesn't expose it here
        }"""
content = content.replace(old_search_context, new_search_context)

# Fix browse
old_browse = """@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, page: int = 1):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/browse?sort=TRENDING_DESC&page={page}&per_page=24")
            data = {"data": {"animes": map_anilist_list(resp.json()), "totalPages": 10, "hasNextPage": True, "currentPage": page}}
        except:
            data = {}
    return templates.TemplateResponse(request=request, name="browse.html", context={"data": data})"""

new_browse = """@app.get("/anime/browse", response_class=HTMLResponse)
async def browse(request: Request, page: int = 1, genres: str = None):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{NEW_API_BASE}/anime/browse?sort=TRENDING_DESC&page={page}&per_page=24")
            data = {"data": {"animes": map_anilist_list(resp.json()), "totalPages": 10, "hasNextPage": True, "currentPage": page}}
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="browse.html", 
        context={
            "data": data,
            "genres": genres or "",
            "selected_genres": [g.strip() for g in genres.split(',')] if genres else [],
            "all_genres": {}
        }
    )"""

content = content.replace(old_browse, new_browse)

with open('app/main.py', 'w') as f:
    f.write(content)
print("Added selected_genres to search and browse routes!")
