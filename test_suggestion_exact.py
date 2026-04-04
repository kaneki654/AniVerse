import asyncio
import httpx
from urllib.parse import quote

NEW_API_BASE = "http://localhost:8001"

async def run():
    q = "demon slayer"
    async with httpx.AsyncClient() as client:
        try:
            url = f"{NEW_API_BASE}/anime/search/{quote(q)}"
            print("URL:", url)
            resp = await client.get(url)
            print("Status:", resp.status_code)
            data = resp.json()
            if isinstance(data, list):
                suggestions = [{"id": item["id"], "name": item["title"].get("english") or item["title"].get("romaji"), "poster": item["coverImage"]["large"], "moreInfo": ["Anime"]} for item in data[:5]]
                print({"data": {"suggestions": suggestions}})
            else:
                print({"data": {"suggestions": []}})
        except Exception as e:
            print("Exception:", e)

asyncio.run(run())
