import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, 'tying-the-knot-with-an-amagami-sister', 1)
        servers = await p.get_servers(client, ep, category='dub')
        
        otakuhg_url = next((s["url"] for s in servers if "otakuhg" in s["url"] or "streamhg" in s["name"].lower()), None)
        
        # 1. Get the embed page to grab the cookies
        r = await client.get(otakuhg_url, headers={"User-Agent": UA, "Referer": "https://anitaku.to/"})
        cookies = dict(client.cookies)
        print("Cookies grabbed:", cookies)
        
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
                
                # 2. Test M3U8 with cookies on a NEW client
                async with httpx.AsyncClient() as client2:
                    print("\n--- Testing M3U8 with NO cookies ---")
                    r1 = await client2.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site/"})
                    print("Status NO Cookies:", r1.status_code)
                    
                    print("\n--- Testing M3U8 WITH cookies ---")
                    r2 = await client2.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site/"}, cookies=cookies)
                    print("Status WITH Cookies:", r2.status_code)
                    if r2.status_code == 200:
                        print("Success! StreamHG works if we forward cookies!")
                    else:
                        print("Failed. Content:", r2.text[:100])

asyncio.run(run())
