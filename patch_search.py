import re

with open('app/main.py', 'r') as f:
    content = f.read()

# I will replace the existing search and browse routes with a unified /search route.
# Find the block from def browse to the end of def search
pattern = re.compile(r'@app\.get\("/anime/browse".*?return templates\.TemplateResponse\(\s*request=request,\s*name="search\.html",\s*context=\{"data": data, "query": q, "page": page\}\s*\)', re.DOTALL)

unified_search_route = """@app.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = "", genres: str = None, page: int = 1):
    all_genres = [
        "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
        "Fantasy", "Game", "Harem", "Historical", "Horror", "Isekai", "Josei", "Kids", 
        "Magic", "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
        "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
        "Shounen", "Slice of Life", "Space", "Sports", "Super Power", "Supernatural", 
        "Thriller", "Vampire"
    ]
    
    selected_genres = [g.strip() for g in genres.split(',')] if genres else []
    
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
            elif resp.status_code == 400 and genres and not q:
                # Fallback if empty query is rejected but genres are provided
                fallback_url = f"{API_BASE}/search?page={page}&q=a&genres={genres}"
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
    )"""

new_content, count = pattern.subn(unified_search_route, content)

if count == 0:
    print("Warning: Could not find the browse/search routes to replace. Let me try another way.")
else:
    with open('app/main.py', 'w') as f:
        f.write(new_content)
    print("Successfully replaced unified search route.")
