import asyncio
import httpx
import urllib.parse
from bs4 import BeautifulSoup
from selectolax.parser import HTMLParser

async def test():
    # Fetch episode page via proxy
    target = "https://anitaku.pe/jujutsu-kaisen-tv-episode-1"
    url = f"https://corsproxy.io/?url={urllib.parse.quote(target)}"
    async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
        try:
            resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
            print("Ep Status:", resp.status_code)
            
            tree = HTMLParser(resp.text)
            servers = []
            for li in tree.css(".anime_muti_link ul li"):
                embed_link = li.attributes.get("data-video")
                if embed_link:
                    if embed_link.startswith("//"):
                        embed_link = "https:" + embed_link
                    servers.append(embed_link)
            
            print("Found embed links:", servers)
            
            if servers:
                # Fetch embed page
                embed_target = servers[0]
                embed_url = f"https://corsproxy.io/?url={urllib.parse.quote(embed_target)}"
                resp2 = await client.get(embed_url, headers={"User-Agent": "Mozilla/5.0"})
                print("Embed Status:", resp2.status_code)
                if resp2.status_code == 200:
                    tree2 = HTMLParser(resp2.text)
                    script_tag = tree2.css_first("script[data-name='episode']")
                    if script_tag:
                        print("Encrypted payload length:", len(script_tag.attributes.get("data-value", "")))
                    else:
                        print("Failed to find script tag")
        except Exception as e:
            print("Error:", e)

asyncio.run(test())
