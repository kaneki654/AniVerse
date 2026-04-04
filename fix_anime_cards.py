import re

# 1. Update map_anilist_list in app/main.py to include rank
with open('app/main.py', 'r') as f:
    main_content = f.read()

old_map_func = """def map_anilist_list(items):
    mapped = []
    for item in items:
        mapped.append({
            "id": item["id"],
            "name": item["title"].get("english") or item["title"].get("romaji"),
            "poster": item["coverImage"]["large"],
            "rank": "?"
        })
    return mapped"""

new_map_func = """def map_anilist_list(items):
    mapped = []
    for idx, item in enumerate(items):
        mapped.append({
            "id": item.get("id"),
            "name": item.get("title", {}).get("english") or item.get("title", {}).get("romaji"),
            "poster": item.get("coverImage", {}).get("large"),
            "rank": str(idx + 1)
        })
    return mapped"""

if old_map_func in main_content:
    main_content = main_content.replace(old_map_func, new_map_func)
    with open('app/main.py', 'w') as f:
        f.write(main_content)
    print("Updated map_anilist_list rank logic in app/main.py")
else:
    print("Could not find map_anilist_list in app/main.py")

# 2. Update get_recently_updated in AniVerseApiUrl/app/services/anilist.py
anilist_path = 'AniVerseApiUrl/app/services/anilist.py'
with open(anilist_path, 'r') as f:
    anilist_content = f.read()

old_recently = """    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
              id
              title { romaji english }
              coverImage { large }
              episodes
            }
          }
        }
        '''"""

new_recently = """    @classmethod
    async def get_recently_updated(cls, page: int = 1, per_page: int = 20) -> List[Dict[str, Any]]:
        graphql_query = '''
        query ($page: Int, $perPage: Int) {
          Page (page: $page, perPage: $perPage) {
            media (type: ANIME, sort: UPDATED_AT_DESC, isAdult: false) {
              id
              title { romaji english }
              coverImage { large }
              episodes
              nextAiringEpisode { episode }
            }
          }
        }
        '''"""

if old_recently in anilist_content:
    anilist_content = anilist_content.replace(old_recently, new_recently)
    with open(anilist_path, 'w') as f:
        f.write(anilist_content)
    print("Updated get_recently_updated in anilist.py")
else:
    print("Could not find get_recently_updated in anilist.py")

# 3. Update the episodes formatting in app/main.py home route
with open('app/main.py', 'r') as f:
    main_content = f.read()

old_latest = """            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                item["episodes"] = item.get("episodes")"""

new_latest = """            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                ep_count = "?"
                if item.get("nextAiringEpisode"):
                    ep = item["nextAiringEpisode"]["episode"]
                    ep_count = str(ep - 1) if ep > 1 else "1"
                elif item.get("episodes"):
                    ep_count = str(item["episodes"])
                    
                item["episodes"] = {"sub": ep_count}"""

if old_latest in main_content:
    main_content = main_content.replace(old_latest, new_latest)
    with open('app/main.py', 'w') as f:
        f.write(main_content)
    print("Updated latest_list episodes logic in app/main.py")
else:
    # Try another variation that might be in the code
    old_latest2 = """            latest_list = latest.json() if isinstance(latest.json(), list) else []
            for item in latest_list:
                item["episodes"] = {"sub": item.get("episodes") or "?"}"""
    if old_latest2 in main_content:
        main_content = main_content.replace(old_latest2, new_latest)
        with open('app/main.py', 'w') as f:
            f.write(main_content)
        print("Updated latest_list episodes logic in app/main.py (Variant 2)")
    else:
        print("Could not find latest_list episodes logic in app/main.py")
