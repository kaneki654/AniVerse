import asyncio
import httpx
import urllib.parse
import json

async def test():
    target_url = "https://anitaku.so/search.html?keyword=jujutsu"
    proxy_url = f"https://api.allorigins.win/get?url={urllib.parse.quote(target_url)}"
    
    async with httpx.AsyncClient(timeout=15) as client:
        try:
            resp = await client.get(proxy_url)
            print("Status:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                contents = data.get("contents", "")
                print("Length:", len(contents))
                if "Jujutsu Kaisen" in contents:
                    print("Success! Bypassed CF.")
        except Exception as e:
            print(e)

asyncio.run(test())
