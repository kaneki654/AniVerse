import json

def deduplicate_animes(animes_list):
    seen = set()
    deduped = []
    for anime in animes_list:
        if anime['id'] not in seen:
            seen.add(anime['id'])
            deduped.append(anime)
    return deduped

# Read main.py
with open('app/main.py', 'r') as f:
    content = f.read()

# Replace home route
import re

old_home_route = """@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(f"{API_BASE}/home")
            data = resp.json()
        except:
            data = {}
    return templates.TemplateResponse(
        request=request, 
        name="home.html", 
        context={"data": data}
    )"""

new_home_route = """@app.get("/", response_class=HTMLResponse)
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
    )"""

content = content.replace(old_home_route, new_home_route)

with open('app/main.py', 'w') as f:
    f.write(content)
