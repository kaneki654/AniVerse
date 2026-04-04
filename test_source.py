import asyncio
from httpx import AsyncClient
from app.main import app

async def run_test():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/api/source?episode_id=16498/1&server=Auto&category=sub")
        print("SOURCE:", response.status_code)
        print("CONTENT:", response.json())

asyncio.run(run_test())
