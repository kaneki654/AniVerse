import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://ajax.gogocdn.net/ajax/page-recent-release.html?page=1")
            print("Ajax CDN:", resp.status_code, len(resp.text))
        except Exception as e:
            print(e)

asyncio.run(test())
