import asyncio
import httpx
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        slug = "shingeki-no-kyojin-dub"
        ep = await p.get_episode(client, slug, 1)
        servers = await p.get_servers(client, ep)
        
        extracted = await p.extract(client, servers)
        streams = extracted.get("streams", [])
        if not streams:
            print("No streams found")
            return
            
        master_url = streams[0]["url"]
        print("Master URL:", master_url)
        
        # Now let's fetch the master m3u8
        resp = await client.get(master_url, headers={"Referer": "https://vibeplayer.site/"})
        print("Master Status:", resp.status_code)
        
        # Read the lines to find the sub-playlist
        lines = resp.text.split('\n')
        sub_playlist_url = None
        for line in lines:
            if line and not line.startswith('#'):
                sub_playlist_url = line
                break
                
        if sub_playlist_url:
            print("Sub Playlist:", sub_playlist_url)
            # Try fetching it immediately
            resp2 = await client.get(sub_playlist_url, headers={"Referer": "https://vibeplayer.site/"})
            print("Sub Playlist Status:", resp2.status_code)
            if resp2.status_code == 403:
                # Try with no referer
                resp3 = await client.get(sub_playlist_url)
                print("Sub Playlist Status (No Referer):", resp3.status_code)
            else:
                print("Sub Playlist content preview:", resp2.text[:100])

asyncio.run(run())
