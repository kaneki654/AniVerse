import asyncio
import httpx

async def run():
    async with httpx.AsyncClient(follow_redirects=True) as client:
        anilist_id = "16498"
        resp = await client.get(f"https://api.malsync.moe/mal/anime/{anilist_id}")
        if resp.status_code == 200:
            sites = resp.json().get("Sites", {})
            gogo_sites = sites.get("Gogoanime", {})
            print("Gogo sites:")
            for key, site_info in gogo_sites.items():
                print(site_info.get("title"), "->", site_info.get("url").split("/")[-1])
        else:
            print("Malsync failed", resp.status_code)

asyncio.run(run())
