with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_mapping = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Use Ani.zip API to get the Gogoanime slug from AniList ID"""
        try:
            resp = await client.get(f"https://api.ani.zip/mappings?anilist_id={anilist_id}")
            if resp.status_code == 200:
                data = resp.json()
                if "mappings" in data:
                    mappings = data["mappings"]
                    if category == "dub":
                        if "gogoanime_dub" in mappings:
                            return mappings["gogoanime_dub"]
                        elif "gogoanime" in mappings:
                            return mappings["gogoanime"] + "-dub"
                    else:
                        if "gogoanime" in mappings:
                            return mappings["gogoanime"]
        except Exception as e:
            print(f"Mapping error: {e}")
        return ""'''

new_mapping = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
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

content = content.replace(old_mapping, new_mapping)

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
    f.write(content)
print("Updated GogoAnimeProvider to use MalSync for mappings!")
