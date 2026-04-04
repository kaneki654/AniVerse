import asyncio
import httpx

async def test():
    urls = [
        "https://api.amvstr.me/api/v2/stream/101280/1",
        "https://api.amvstr.ml/api/v2/stream/101280/1"
    ]
    async with httpx.AsyncClient(timeout=10) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code}")
                if resp.status_code == 200:
                    print(resp.json())
            except Exception as e:
                print(f"{url}: {e}")

asyncio.run(test())
