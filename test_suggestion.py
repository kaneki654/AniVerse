import asyncio
import httpx
from urllib.parse import quote

async def run():
    async with httpx.AsyncClient() as client:
        q = "demon slayer"
        resp = await client.get(f"http://localhost:8001/anime/search/{quote(q)}")
        data = resp.json()
        print("Data is list?", isinstance(data, list))
        print("Data length:", len(data))
        
        suggestions = []
        for item in data[:5]:
            try:
                name = item.get("title", {}).get("english") or item.get("title", {}).get("romaji")
                poster = item.get("coverImage", {}).get("large")
                suggestions.append({
                    "id": item["id"],
                    "name": name,
                    "poster": poster,
                    "moreInfo": ["Anime"]
                })
            except Exception as e:
                print("Error in comprehension:", e)
        print("Suggestions:", suggestions)

asyncio.run(run())
