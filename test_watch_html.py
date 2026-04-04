import asyncio
from httpx import AsyncClient
from app.main import app

async def run_test():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/watch/16498/1")
        html = response.text
        # extract serversData line
        for line in html.split('\n'):
            if 'serversData =' in line:
                print(line.strip())

asyncio.run(run_test())
