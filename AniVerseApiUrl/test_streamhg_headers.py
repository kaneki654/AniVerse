import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        ep = await p.get_episode(client, "tying-the-knot-with-an-amagami-sister", 1)
        servers = await p.get_servers(client, ep, category="dub")
        
        otakuhg_url = next((s["url"] for s in servers if "otakuhg" in s["url"] or "streamhg" in s["name"].lower()), None)
        
        r = await client.get(otakuhg_url, headers={"User-Agent": UA, "Referer": "https://anitaku.to/"})
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
                
                # Test 1
                resp1 = await client.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site/", "Origin": "https://otakuhg.site"})
                print("otakuhg referer/origin:", resp1.status_code)
                
                # Test 2
                resp2 = await client.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site"})
                print("otakuhg referer no slash:", resp2.status_code)
                
                # Test 3
                resp3 = await client.get(fresh_url, headers={"User-Agent": UA, "Referer": otakuhg_url})
                print("exact url referer:", resp3.status_code)
                
                # Test 4
                resp4 = await client.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://anitaku.to/"})
                print("anitaku referer:", resp4.status_code)

asyncio.run(run())
