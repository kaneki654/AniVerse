import asyncio
import httpx

headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

async def test():
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        resp = await client.get("https://anitaku.bz/search.html?keyword=jujutsu+kaisen")
        print("bz status:", resp.status_code)
        print("bz len:", len(resp.text))
        
        resp2 = await client.get("https://gogoanime3.co/search.html?keyword=jujutsu+kaisen")
        print("co status:", resp2.status_code)
        print("co len:", len(resp2.text))

asyncio.run(test())
