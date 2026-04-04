import asyncio
import httpx
import time

async def run():
    start = time.time()
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get("http://localhost:8000/api/source?episode_id=164172/1&server=Auto&category=sub")
            print("Status:", resp.status_code)
            print("Response:", resp.json())
    except Exception as e:
        print("Error:", e)
    print("Time taken:", time.time() - start)

asyncio.run(run())
