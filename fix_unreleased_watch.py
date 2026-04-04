import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_query = """    query = '''
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        title { romaji english }
        coverImage { large }
        episodes
      }
    }
    '''"""

new_query = """    query = '''
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        title { romaji english }
        coverImage { large }
        episodes
        status
      }
    }
    '''"""

if old_query in content:
    content = content.replace(old_query, new_query)

old_media_parse = """                anime_info["name"] = media["title"].get("english") or media["title"].get("romaji")
                anime_info["poster"] = media["coverImage"]["large"]
                ep_count = media.get("episodes") or 12"""

new_media_parse = """                anime_info["name"] = media["title"].get("english") or media["title"].get("romaji")
                anime_info["poster"] = media["coverImage"]["large"]
                anime_info["status"] = media.get("status")
                
                if anime_info["status"] == "NOT_YET_RELEASED":
                    return HTMLResponse("<div style='color:white; text-align:center; padding:50px; font-family:sans-serif;'><h2>This Anime Hasn't been release yet</h2><a href='/' style='color:#e50914;'>Go Home</a></div>", status_code=403)
                    
                ep_count = media.get("episodes") or 12"""

if old_media_parse in content:
    content = content.replace(old_media_parse, new_media_parse)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed watch page for unreleased anime!")
else:
    print("Could not find the watch page logic to fix.")
