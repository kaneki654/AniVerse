import asyncio
import httpx

async def test():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        try:
            resp = await client.get("https://www.wcofun.net/search", headers={"User-Agent": "Mozilla/5.0"})
            print("WCO:", resp.status_code, len(resp.text))
        except Exception as e:
            print(e)

asyncio.run(test())
