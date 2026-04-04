import asyncio
import httpx

async def test():
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        resp = await client.get("https://hianime.to/search?keyword=jujutsu+kaisen")
        print("Status:", resp.status_code)
        if "Just a moment..." in resp.text:
            print("Cloudflare Blocked!")
        else:
            print("HTML Snippet:", resp.text[:500])

asyncio.run(test())
