import asyncio
from app.main import app
from httpx import AsyncClient

async def run_test():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/")
        print("HOME:", response.status_code)
        
        response2 = await ac.get("/anime/16498")
        print("DETAIL:", response2.status_code)
        
        response3 = await ac.get("/watch/16498/1")
        print("WATCH:", response3.status_code)

asyncio.run(run_test())
