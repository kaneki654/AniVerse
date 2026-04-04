import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        # Get MAL ID from AniList ID using Ani.zip
        try:
            resp1 = await client.get("https://api.ani.zip/mappings?anilist_id=101280")
            mal_id = resp1.json().get("mappings", {}).get("mal_id")
            print("MAL ID:", mal_id)
            
            # Query MALSync
            resp2 = await client.get(f"https://api.malsync.moe/mal/anime/{mal_id}")
            print("MALSync Status:", resp2.status_code)
            data = resp2.json()
            
            # Check Gogoanime
            gogo = data.get("Sites", {}).get("Gogoanime", {})
            if gogo:
                print("GogoAnime Keys:", list(gogo.keys()))
                first_key = list(gogo.keys())[0]
                print("GogoAnime URL:", gogo[first_key].get("url"))
                
            # Check Zoro
            zoro = data.get("Sites", {}).get("Zoro", {})
            if zoro:
                print("Zoro Keys:", list(zoro.keys()))
                first_key = list(zoro.keys())[0]
                print("Zoro URL:", zoro[first_key].get("url"))

        except Exception as e:
            print("Error:", e)

asyncio.run(test())
