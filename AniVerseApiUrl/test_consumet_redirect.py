import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://api.consumet.org/meta/anilist/info/101280", follow_redirects=False)
            print("Status:", resp.status_code)
            print("Location:", resp.headers.get("location"))
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
