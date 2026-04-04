import asyncio
import httpx

async def test():
    urls = [
        "https://api-consumet.xyz",
        "https://api.consumet.org",
        "https://consumet.vercel.app",
        "https://anify.rest",
        "https://api.amvstr.ml",
        "https://api.aniskip.com",
    ]
    async with httpx.AsyncClient(timeout=5) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code}")
            except Exception as e:
                print(f"{url}: {e}")

asyncio.run(test())
