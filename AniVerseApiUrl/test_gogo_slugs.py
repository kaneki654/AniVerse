import asyncio
import httpx

async def run():
    slugs_to_try = [
        "attack-on-titan-dub",
        "shingeki-no-kyojin-dub",
        "shingeki-no-kyojin-tv-dub",
        "attack-on-titan-tv-dub",
        "attack-on-titan-season-1-dub",
        "shingeki-no-kyojin-season-1-dub",
        "attack-on-titan-part-1-dub",
        "shingeki-no-kyojin-part-1-dub"
    ]
    async with httpx.AsyncClient(follow_redirects=True) as client:
        for slug in slugs_to_try:
            r = await client.get(f"https://anitaku.to/category/{slug}")
            if "Pages not found" not in r.text:
                print("FOUND:", slug)
            else:
                print("Not found:", slug)
                
asyncio.run(run())
