import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("http://localhost:8001/anime/resolve/164172/1?category=sub", timeout=10)
            print("Status:", resp.status_code)
        except Exception as e:
            print("Error:", e)

asyncio.run(run())
