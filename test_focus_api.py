import asyncio
import httpx
import time

async def run():
    start = time.time()
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            url = 'http://localhost:8001/anime/latest?per_page=12'
            resp = await client.get(url)
            print("Latest API:", resp.status_code)
    except Exception as e:
        print('Error:', e)
    print('Time:', time.time() - start)
asyncio.run(run())
