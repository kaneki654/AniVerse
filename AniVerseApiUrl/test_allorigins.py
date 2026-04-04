import asyncio
import httpx
import urllib.parse
from selectolax.parser import HTMLParser

async def test():
    # Fetch episode page via allorigins
    target = "https://anitaku.pe/jujutsu-kaisen-tv-episode-1"
    url = f"https://api.allorigins.win/get?url={urllib.parse.quote(target)}"
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        try:
            resp = await client.get(url)
            print("Ep Status:", resp.status_code)
            if resp.status_code == 200:
                data = resp.json()
                html = data.get("contents", "")
                print("HTML Length:", len(html))
                
                tree = HTMLParser(html)
                servers = []
                for li in tree.css(".anime_muti_link ul li"):
                    embed_link = li.attributes.get("data-video")
                    if embed_link:
                        if embed_link.startswith("//"):
                            embed_link = "https:" + embed_link
                        servers.append(embed_link)
                
                print("Found embed links:", servers)
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
