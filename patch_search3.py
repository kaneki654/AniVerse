import re

with open('app/main.py', 'r') as f:
    content = f.read()

# I will replace the unified search route definition to pass dict of genres
search_func_pattern = re.compile(r'(@app\.get\("/search", response_class=HTMLResponse\)\nasync def search\(request: Request, q: str = "", genres: str = None, page: int = 1\):).*?(data = \{\})', re.DOTALL)

def replace_search(match):
    header = match.group(1)
    new_body = """
    all_genres_list = [
        "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
        "Fantasy", "Game", "Harem", "Historical", "Horror", "Isekai", "Josei", "Kids", 
        "Magic", "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
        "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
        "Shounen", "Slice of Life", "Space", "Sports", "Super Power", "Supernatural", 
        "Thriller", "Vampire", "Yaoi", "Yuri", "Shoujo Ai", "Shounen Ai"
    ]
    all_genres = {g.lower().replace(" ", "-"): g for g in all_genres_list}
    
    # genres will come in as 'action,slice-of-life'
    selected_genres = [g.strip().lower() for g in genres.split(',')] if genres else []
    
    data = {}"""
    return header + new_body

content = search_func_pattern.sub(replace_search, content)

with open('app/main.py', 'w') as f:
    f.write(content)
