import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://api.anify.tv/sources?providerId=gogoanime&watchId=jujutsu-kaisen-tv-episode-1&episodeNumber=1&id=101280&subType=sub", timeout=10)
            print("Anify:", resp.status_code)
            if resp.status_code == 200:
                print(json.dumps(resp.json(), indent=2)[:500])
        except Exception as e:
            print("Anify Error:", e)

asyncio.run(test())
