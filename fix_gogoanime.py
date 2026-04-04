import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

# 1. Fix base_url
content = content.replace('return "https://anitaku.pe"', 'return "https://anitaku.to"')

# 2. Rewrite map_anime
old_mapping = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Use MalSync API to get the Gogoanime slug from AniList ID"""
        try:
            # 1. Get MAL ID from Ani.zip (since MalSync uses MAL ID)
            mal_id = None
            ani_resp = await client.get(f"https://api.ani.zip/mappings?anilist_id={anilist_id}")
            if ani_resp.status_code == 200:
                mal_id = ani_resp.json().get("mappings", {}).get("mal_id")
            
            if not mal_id:
                # Fallback to search if no MAL ID?
                return ""
                
            # 2. Get Gogoanime slug from MalSync
            mal_resp = await client.get(f"https://api.malsync.moe/mal/anime/{mal_id}")
            if mal_resp.status_code == 200:
                sites = mal_resp.json().get("Sites", {})
                gogo_sites = sites.get("Gogoanime", {})
                
                # Usually there are multiple entries if there are dubs
                slug = ""
                for key, site_info in gogo_sites.items():
                    title = site_info.get("title", "").lower()
                    if category == "dub" and "(dub)" in title:
                        slug = site_info.get("url", "").split("/")[-1]
                        break
                    elif category == "sub" and "(dub)" not in title:
                        slug = site_info.get("url", "").split("/")[-1]
                        break
                
                # If we couldn't find an exact match, just take the first one and append -dub if needed
                if not slug and gogo_sites:
                    first_site = list(gogo_sites.values())[0]
                    slug = first_site.get("url", "").split("/")[-1]
                    if category == "dub" and not slug.endswith("-dub"):
                        slug += "-dub"
                
                return slug
                
        except Exception as e:
            print(f"MalSync Mapping error: {e}")
        return ""'''

new_mapping = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Use AniList Title to search GogoAnime directly"""
        import re
        try:
            # 1. Get Title from AniList
            query = """
            query ($id: Int) {
              Media (id: $id, type: ANIME) {
                title { romaji english }
              }
            }
            """
            resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"id": int(anilist_id)}})
            data = resp.json().get("data", {}).get("Media", {})
            title = data.get("title", {}).get("english") or data.get("title", {}).get("romaji")
            if not title: return ""
            
            # 2. Search GogoAnime
            import urllib.parse
            search_url = f"{self.base_url}/search.html?keyword={urllib.parse.quote(title)}"
            search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
            
            # 3. Parse first result
            matches = re.findall(r'<p class="name"><a href="/category/([^"]+)"', search_resp.text)
            if matches:
                # Find the best match
                # Often the exact match is just the first one. Let's look for exact dub if needed.
                slug = matches[0]
                
                # If they want dub, let's see if there's a specific dub slug in the results
                if category == "dub":
                    dub_slug = next((m for m in matches if "dub" in m.lower()), None)
                    if dub_slug:
                        return dub_slug
                    else:
                        return slug + "-dub"
                else:
                    # They want sub. Avoid dubs if possible.
                    sub_slug = next((m for m in matches if "dub" not in m.lower()), None)
                    return sub_slug if sub_slug else slug

        except Exception as e:
            print(f"Gogo Search error: {e}")
        return ""'''

if old_mapping in content:
    content = content.replace(old_mapping, new_mapping)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed GogoAnimeProvider!")
else:
    print("Could not find the old mapping function in gogoanime.py")
