import asyncio
import httpx

async def main():
    async with httpx.AsyncClient() as client:
        for slug in ["my-star-season-2", "my-star-season-2-dub", "oshi-no-ko-2nd-season", "oshi-no-ko-2nd-season-dub"]:
            r = await client.get(f"https://anitaku.to/{slug}-episode-1")
            print(f"{slug}: {r.status_code}")

asyncio.run(main())
