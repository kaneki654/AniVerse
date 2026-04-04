import asyncio
import httpx

async def run():
    async with httpx.AsyncClient() as client:
        r1 = await client.get("https://anitaku.to/category/shingeki-no-kyojin-dub", follow_redirects=True)
        print("shingeki-no-kyojin-dub:", "<title>" in r1.text, r1.text.split("<title>")[1].split("</title>")[0] if "<title>" in r1.text else "")
        r2 = await client.get("https://anitaku.to/category/attack-on-titan-dub", follow_redirects=True)
        print("attack-on-titan-dub:", "<title>" in r2.text, r2.text.split("<title>")[1].split("</title>")[0] if "<title>" in r2.text else "")

asyncio.run(run())
