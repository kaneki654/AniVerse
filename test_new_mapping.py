import asyncio
import httpx
import re
import urllib.parse

async def map_anime(client, anilist_id, category):
    try:
        query = """
        query ($id: Int) {
          Media (id: $id, type: ANIME) {
            title { romaji english }
          }
        }
        """
        resp = await client.post("https://graphql.anilist.co", json={"query": query, "variables": {"id": int(anilist_id)}})
        data = resp.json().get("data", {}).get("Media", {})
        title_en = data.get("title", {}).get("english", "")
        title_ro = data.get("title", {}).get("romaji", "")
        
        def clean_title(t):
            if not t: return ""
            t = re.sub(r'[\[\]\(\)]', '', t)
            return t.strip()
            
        titles_to_try = [clean_title(title_en), clean_title(title_ro)]
        
        for t in titles_to_try:
            if not t: continue
            search_url = f"https://anitaku.to/search.html?keyword={urllib.parse.quote(t)}"
            search_resp = await client.get(search_url, headers={"User-Agent": "Mozilla/5.0"})
            
            matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
            matches = list(dict.fromkeys(matches))
            
            if matches:
                slug = matches[0]
                if category == "dub":
                    check_url = f"https://anitaku.to/category/{slug}-dub"
                    try:
                        r = await client.head(check_url, follow_redirects=True)
                        if r.status_code == 200:
                            return f"{slug}-dub"
                    except Exception:
                        pass
                return slug
                
    except Exception as e:
        print(f"error: {e}")
    return ""

async def main():
    async with httpx.AsyncClient() as client:
        print("166531 SUB:", await map_anime(client, "166531", "sub"))
        print("166531 DUB:", await map_anime(client, "166531", "dub"))
        print("164172 SUB:", await map_anime(client, "164172", "sub"))
        print("164172 DUB:", await map_anime(client, "164172", "dub"))

asyncio.run(main())
