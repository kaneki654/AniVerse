import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://yugenanime.tv/search/?q=jujutsu", timeout=10)
            print("Yugen status:", resp.status_code)
            print("Yugen len:", len(resp.text))
        except Exception as e:
            print(e)
            
        try:
            resp = await client.get("https://animepahe.ru/api?m=search&q=jujutsu", timeout=10)
            print("Pahe status:", resp.status_code)
            print("Pahe len:", len(resp.text))
        except Exception as e:
            print(e)

asyncio.run(test())
