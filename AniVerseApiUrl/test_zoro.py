import asyncio
import httpx

async def test():
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get("https://hianime.to/ajax/v2/episode/servers?episodeId=1")
            print("Zoro:", resp.status_code, len(resp.text))
        except Exception as e:
            print(e)

asyncio.run(test())
