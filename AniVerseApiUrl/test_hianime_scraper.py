import asyncio
import httpx
from bs4 import BeautifulSoup

async def run():
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Search for Amagami Sister
        url = "https://hianime.to/search?keyword=Tying+the+Knot+with+an+Amagami+Sister"
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        
        soup = BeautifulSoup(resp.text, 'html.parser')
        first_result = soup.select_one(".film_list-wrap .flw-item .film-detail .film-name a")
        if not first_result:
            print("No results on hianime")
            return
            
        anime_id = first_result['href'].split('/')[-1]
        print("HiAnime ID:", anime_id)
        
        # Get episodes
        episodes_url = f"https://hianime.to/ajax/v2/episode/list/{anime_id.split('-')[-1]}"
        resp2 = await client.get(episodes_url, headers={"User-Agent": "Mozilla/5.0", "Referer": f"https://hianime.to/watch/{anime_id}"})
        data = resp2.json()
        
        ep_soup = BeautifulSoup(data.get("html", ""), 'html.parser')
        ep1 = ep_soup.select_one(".ep-item")
        if not ep1:
            print("No episodes found")
            return
            
        ep_id = ep1['data-id']
        print("HiAnime Episode 1 ID:", ep_id)
        
        # Get servers
        servers_url = f"https://hianime.to/ajax/v2/episode/servers?episodeId={ep_id}"
        resp3 = await client.get(servers_url, headers={"User-Agent": "Mozilla/5.0"})
        servers_data = resp3.json()
        
        servers_html = servers_data.get("html", "")
        print("Servers HTML length:", len(servers_html))
        
        s_soup = BeautifulSoup(servers_html, 'html.parser')
        # Check dub servers
        dub_servers = s_soup.select(".servers-dub .server-item")
        print("Dub servers:", [s['data-server-id'] for s in dub_servers])

asyncio.run(run())
