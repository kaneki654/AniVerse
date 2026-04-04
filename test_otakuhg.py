import asyncio
import httpx

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://otakuhg.site/e/cjqev3hl9rif", headers={"User-Agent": "Mozilla/5.0"})
        print("Status:", r.status_code)
        
        # Look for m3u8 in text
        for line in r.text.split('\n'):
            if 'm3u8' in line:
                print(line.strip())

asyncio.run(main())
