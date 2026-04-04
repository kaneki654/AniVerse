import asyncio
import httpx
import urllib.parse

async def test():
    target = "https://anitaku.pe/search.html?keyword=jujutsu+kaisen"
    url = f"https://corsproxy.io/?url={urllib.parse.quote(target)}"
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            print(resp.status_code)
            if "Just a moment..." in resp.text:
                print("Blocked by CF")
            else:
                print("Length:", len(resp.text))
        except Exception as e:
            print(e)

asyncio.run(test())
