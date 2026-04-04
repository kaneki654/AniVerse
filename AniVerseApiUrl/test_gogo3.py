import asyncio
import httpx

async def test():
    urls = [
        "https://anitaku.so/search.html?keyword=jujutsu+kaisen",
        "https://gogoanime.hu/search.html?keyword=jujutsu+kaisen",
        "https://gogoanime3.co/search.html?keyword=jujutsu+kaisen"
    ]
    async with httpx.AsyncClient(follow_redirects=True, timeout=10) as client:
        for url in urls:
            try:
                resp = await client.get(url)
                print(f"{url}: {resp.status_code} - len {len(resp.text)}")
            except Exception as e:
                print(f"{url}: {e}")

asyncio.run(test())
