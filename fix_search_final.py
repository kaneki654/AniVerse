with open('app/main.py', 'r') as f:
    content = f.read()

start_str = '@app.get("/search", response_class=HTMLResponse)'
end_str = '@app\\.get\\("/anime/\\{anime_id\\}", response_class=HTMLResponse\\)'

start_idx = content.find(start_str)
end_idx = content.find(end_str)

if start_idx != -1 and end_idx != -1:
    new_code = """@app.get("/search", response_class=HTMLResponse)
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
"""
    content = content[:start_idx] + new_code + content[end_idx + len(end_str):]
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Successfully replaced search and browse routes!")
else:
    print("Could not find start or end strings.")
