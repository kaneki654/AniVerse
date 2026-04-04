import asyncio
import httpx
import urllib.parse

async def test():
    target = "https://anitaku.pe/jujutsu-kaisen-tv-episode-1"
    url = f"https://corsproxy.io/?url={urllib.parse.quote(target)}"
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            print(resp.text[:500])
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
