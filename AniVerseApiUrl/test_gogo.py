import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        resp = await client.get("https://anitaku.pe/search.html?keyword=jujutsu+kaisen")
        with open("search.html", "w") as f:
            f.write(resp.text)
asyncio.run(test())
