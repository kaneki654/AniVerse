import asyncio
import httpx
from selectolax.parser import HTMLParser

async def get_servers(episode_id, category):
    async with httpx.AsyncClient() as client:
        r = await client.get(f"https://anitaku.to/{episode_id}")
        if r.status_code != 200: return []
        tree = HTMLParser(r.text)
        
        div_class = "type_DUB" if category == "dub" else "type_SUB"
        div = tree.css_first(f"div.{div_class}")
        
        if div:
            links = div.css("ul li a")
        elif category == "dub" and "-dub-" not in episode_id:
            return []
        else:
            links = tree.css(".anime_muti_link ul li a")
            
        return [li.text(strip=True) for li in links] if links else []

async def main():
    print("my-star sub:", await get_servers("my-star-season-2-episode-1", "sub"))
    print("my-star dub:", await get_servers("my-star-season-2-episode-1", "dub"))
    print("amagami sub:", await get_servers("tying-the-knot-with-an-amagami-sister-episode-1", "sub"))
    print("amagami dub:", await get_servers("tying-the-knot-with-an-amagami-sister-episode-1", "dub"))

asyncio.run(main())
