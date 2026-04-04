with open('app/main.py', 'r') as f:
    content = f.read()

old_suggest = """@app.get("/search/suggestion")
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
            return {"suggestions": []}"""

new_suggest = """@app.get("/search/suggestion")
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
            return {"data": {"suggestions": []}}"""

if old_suggest in content:
    content = content.replace(old_suggest, new_suggest)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed search_suggestion endpoint!")
else:
    print("Could not find the search_suggestion code.")
