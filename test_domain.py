import asyncio
import httpx
import urllib.parse

async def main():
    embed_url = "https://otakuhg.site/e/j217x3yvlmjn"
    parsed = urllib.parse.urlparse(embed_url)
    video_id = parsed.path.split("/")[-1]
    
    async with httpx.AsyncClient() as client:
        print("Trying vibeplayer domain...")
        try:
            r1 = await client.get(f"https://vibeplayer.site/public/stream/{video_id}/master.m3u8")
            print("vibeplayer status:", r1.status_code)
        except Exception as e:
            print("vibeplayer error:", e)
        
        print("Trying otakuhg domain...")
        try:
            r2 = await client.get(f"https://otakuhg.site/public/stream/{video_id}/master.m3u8")
            print("otakuhg status:", r2.status_code)
        except Exception as e:
            print("otakuhg error:", e)

asyncio.run(main())
