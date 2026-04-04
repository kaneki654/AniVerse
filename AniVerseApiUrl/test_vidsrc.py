import asyncio
import httpx

async def test():
    urls = [
        "https://vidsrc.me/embed/tv/95479/1/1",
        "https://vidsrc.to/embed/tv/95479/1/1"
    ]
    async with httpx.AsyncClient(timeout=10, follow_redirects=True) as client:
        for url in urls:
            try:
                resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
                print(f"{url} -> {resp.status_code}")
                if "Just a moment..." in resp.text:
                    print("Cloudflare Blocked!")
                else:
                    print("Length:", len(resp.text))
            except Exception as e:
                print("Error:", e)

asyncio.run(test())
