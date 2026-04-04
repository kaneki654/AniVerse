import asyncio
import httpx

async def test():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            resp = await client.get("https://hianime.to/search?keyword=jujutsu")
            print("Status:", resp.status_code, "Length:", len(resp.text))
            if "Just a moment..." in resp.text:
                print("Cloudflare Blocked!")
        except Exception as e:
            print(e)

asyncio.run(test())
