import asyncio
import httpx
from bs4 import BeautifulSoup
import json

async def test():
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    async with httpx.AsyncClient(headers=headers, follow_redirects=True) as client:
        # Search
        resp = await client.get("https://hianime.to/search?keyword=jujutsu+kaisen")
        print("Search:", resp.status_code)
        
        from selectolax.parser import HTMLParser
        tree = HTMLParser(resp.text)
        first_result = tree.css_first(".film-detail .film-name a")
        if not first_result:
            print("No result found")
            return
            
        anime_url = first_result.attributes.get("href")
        anime_id = anime_url.split("-")[-1].split("?")[0]
        print("Anime ID:", anime_id)
        
        # Get episodes
        resp_eps = await client.get(f"https://hianime.to/ajax/v2/episode/list/{anime_id}")
        data_eps = resp_eps.json()
        tree_eps = HTMLParser(data_eps.get("html", ""))
        first_ep = tree_eps.css_first(".ep-item")
        if not first_ep:
            print("No episodes")
            return
            
        ep_id = first_ep.attributes.get("data-id")
        print("Episode ID:", ep_id)
        
        # Get servers
        resp_servers = await client.get(f"https://hianime.to/ajax/v2/episode/servers?episodeId={ep_id}")
        data_servers = resp_servers.json()
        tree_servers = HTMLParser(data_servers.get("html", ""))
        first_server = tree_servers.css_first(".server-item")
        if not first_server:
            print("No servers")
            return
            
        server_id = first_server.attributes.get("data-id")
        print("Server ID:", server_id)
        
        # Get embed link
        resp_embed = await client.get(f"https://hianime.to/ajax/v2/episode/sources?id={server_id}")
        print("Embed JSON:", resp_embed.text)

asyncio.run(test())
