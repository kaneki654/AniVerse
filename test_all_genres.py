import asyncio
import httpx
from bs4 import BeautifulSoup

all_genres_list = [
    "Action", "Adventure", "Cars", "Comedy", "Dementia", "Demons", "Drama", "Ecchi",
    "Fantasy", "Game", "Harem", "Historical", "Horror", "Isekai", "Josei", "Kids", 
    "Magic", "Martial Arts", "Mecha", "Military", "Music", "Mystery", "Parody", "Police",
    "Psychological", "Romance", "Samurai", "School", "Sci-Fi", "Seinen", "Shoujo",
    "Shounen", "Slice of Life", "Space", "Sports", "Super Power", "Supernatural", 
    "Thriller", "Vampire", "Yaoi", "Yuri", "Shoujo Ai", "Shounen Ai"
]
all_genres = {g.lower().replace(" ", "-"): g for g in all_genres_list}

async def run():
    async with httpx.AsyncClient() as client:
        for slug in all_genres.keys():
            resp = await client.get(f"http://localhost:8000/search?genres={slug}")
            soup = BeautifulSoup(resp.text, 'html.parser')
            cards = soup.select(".anime-card")
            if len(cards) == 0:
                print(f"Genre {slug} returns ZERO results")

asyncio.run(run())
