import asyncio
import httpx
import urllib.parse
import re

async def main():
    async with httpx.AsyncClient() as client:
        anilist_id = "164172"
        query = """
        query ($id: Int) {
          Media (id: $id, type: ANIME) {
            title { romaji english }
          }
        }
        """
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"id": int(anilist_id)}})
        data = resp.json().get("data", {}).get("Media", {})
        title = data.get("title", {}).get("english") or data.get("title", {}).get("romaji")
        print("Anilist Title:", title)
        
        search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(title)}"
        print("Search URL:", search_url)
        search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
        
        matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
        matches = list(dict.fromkeys(matches)) # Remove duplicates
        print("Matches:", matches)
        
        # If the english title fails to return the right result, let's try romaji
        romaji = data.get("title", {}).get("romaji")
        print("Anilist Romaji Title:", romaji)
        
        search_url2 = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(romaji)}"
        print("Search URL (Romaji):", search_url2)
        search_resp2 = await client.get(search_url2, headers={"User-Agent": "Mozilla/5.0"})
        
        matches2 = re.findall(r'href="/category/([^"]+)"', search_resp2.text)
        matches2 = list(dict.fromkeys(matches2)) # Remove duplicates
        print("Matches (Romaji):", matches2)

asyncio.run(main())
