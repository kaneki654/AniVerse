import asyncio
import httpx

async def test():
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get("https://api.ani.zip/mappings?anilist_id=101280")
            print("Status:", resp.status_code)
            data = resp.json()
            if "mappings" in data and "themoviedb_id" in data["mappings"]:
                print("TMDB ID:", str(data["mappings"]["themoviedb_id"]))
            else:
                print("Keys:", data.keys())
    except Exception as e:
        print("Error:", e)

asyncio.run(test())
