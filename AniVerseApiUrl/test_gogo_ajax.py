import asyncio
import httpx
import json

async def run():
    keyword = "attack on titan"
    url = f"https://ajax.gogocdn.net/site/loadAjaxSearch?keyword=attack%20on%20titan"
    async with httpx.AsyncClient() as client:
        r = await client.get(url)
        try:
            print(r.json())
        except:
            print("Failed to parse JSON", r.status_code, r.text)

asyncio.run(run())
