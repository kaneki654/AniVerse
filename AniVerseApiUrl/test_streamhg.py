import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, 'tying-the-knot-with-an-amagami-sister', 1)
        servers = await p.get_servers(client, ep, category='dub')
        
        otakuhg_url = None
        for s in servers:
            if 'otakuhg' in s['url'] or 'streamhg' in s['name'].lower():
                otakuhg_url = s['url']
                break
                
        if not otakuhg_url:
            print("No otakuhg url found")
            return
            
        print("OtakuHG URL:", otakuhg_url)
        
        r = await client.get(otakuhg_url, headers={"User-Agent": "Mozilla/5.0"})
        match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        if match:
            pv = match.group(1).replace('\\\'', "'")
            av = int(match.group(2))
            cv = int(match.group(3))
            kv = match.group(4).split('|')
            unpacked = p.unpack(pv, av, cv, kv)
            m3u8_links = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
            
            if m3u8_links:
                fresh_url = m3u8_links[0]
                print("Fresh M3U8 URL:", fresh_url)
                
                print("\n--- Testing with Referer: https://otakuhg.site/ ---")
                resp1 = await client.get(fresh_url, headers={"Referer": "https://otakuhg.site/"})
                print(resp1.status_code)
                
                print("\n--- Testing with NO Referer ---")
                resp2 = await client.get(fresh_url)
                print(resp2.status_code)
                
                print("\n--- Testing with Referer: https://cloudnestra.com/ ---")
                resp3 = await client.get(fresh_url, headers={"Referer": "https://cloudnestra.com/"})
                print(resp3.status_code)

asyncio.run(run())
