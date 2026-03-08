with open('app/static/manga_search.js', 'r') as f:
    content = f.read()

# Update manga cover handling in suggestions to match Consumet's format
# Wait, let's also add the suggestion route to main.py
# First update the JS fields to match consumet
content = content.replace('manga.tags', 'manga.genres')
content = content.replace('manga.cover', '`/manga/proxy?url=${encodeURIComponent(manga.image)}`') # We'll need a generic proxy route for this or rely on proxy_base
content = content.replace('?title=', '?q=')

with open('app/static/manga_search.js', 'w') as f:
    f.write(content)

with open('app/main.py', 'r') as f:
    main_content = f.read()

suggestion_route = """@app.get("/manga/search/suggestion")
async def manga_search_suggestion(q: str):
    async with httpx.AsyncClient() as client:
        try:
            url = f"{MANGA_API_BASE}/{q}"
            resp = await client.get(url)
            if resp.status_code == 200:
                # We can just return the raw results from Consumet
                return resp.json()
        except:
            return {"results": []}
    return {"results": []}

@app.get("/manga/proxy")
async def basic_manga_proxy(url: str):
    # Quick proxy for JS suggestions
    proxy_url = MANGA_PROXY + url
    return HTMLResponse(f"<script>window.location.href='{proxy_url}';</script>")

@app.get("/manga/search", response_class=HTMLResponse)"""

main_content = main_content.replace('@app.get("/manga/search", response_class=HTMLResponse)', suggestion_route)

with open('app/main.py', 'w') as f:
    f.write(main_content)
