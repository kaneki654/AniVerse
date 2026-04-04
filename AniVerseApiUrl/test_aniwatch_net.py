import asyncio
import httpx
import json

async def test():
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.get("https://aniwatch-api-net.vercel.app/api/v2/hianime/search?q=jujutsu")
            print("Status:", resp.status_code)
            if resp.status_code == 200:
                print(resp.json())
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
