import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_genres = """    all_genres_list = [
        "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
        "Fantasy", "Game", "Harem", "Historical", "Horror", "Isekai", "Josei", "Kids", 
        "Magic", "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
        "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
        "Shounen", "Slice of Life", "Space", "Sports", "Super Power", "Supernatural", 
        "Thriller", "Vampire", "Yaoi", "Yuri", "Shoujo Ai", "Shounen Ai"
    ]"""

new_genres = """    all_genres_list = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", 
        "Horror", "Mahou Shoujo", "Mecha", "Music", "Mystery", 
        "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", 
        "Supernatural", "Thriller"
    ]"""

if old_genres in content:
    content = content.replace(old_genres, new_genres)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed genres list!")
else:
    print("Could not find the genres list to replace.")
