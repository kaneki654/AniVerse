import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Step 1: Scrape the embed page using the client
        ep = await p.get_episode(client, "tying-the-knot-with-an-amagami-sister", 1)
        servers = await p.get_servers(client, ep, category="dub")
        
        otakuhg_url = next((s["url"] for s in servers if "otakuhg" in s["url"] or "streamhg" in s["name"].lower()), None)
        print("OtakuHG URL:", otakuhg_url)
        
        r = await client.get(otakuhg_url, headers={"User-Agent": UA, "Referer": "https://anitaku.to/"})
        match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        
        if not match:
            print("Eval not found")
            return
            
        pv = match.group(1).replace('\\\'', "'")
        av = int(match.group(2))
        cv = int(match.group(3))
        kv = match.group(4).split('|')
        unpacked = p.unpack(pv, av, cv, kv)
        m3u8_links = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
        
        if m3u8_links:
            fresh_url = m3u8_links[0]
            print("Fresh M3U8 URL:", fresh_url)
            
            # Step 2: Fetch M3U8 using the SAME client (so cookies are shared)
            print("\n--- Testing with shared Client (Cookies preserved) ---")
            resp1 = await client.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site/"})
            print("Status:", resp1.status_code)
            if resp1.status_code != 200:
                print("Body:", resp1.text[:200])
                
            # Step 3: Fetch M3U8 using a NEW client (no cookies, same IP)
            print("\n--- Testing with NEW Client (No cookies, same IP) ---")
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as new_client:
                resp2 = await new_client.get(fresh_url, headers={"User-Agent": UA, "Referer": "https://otakuhg.site/"})
                print("Status:", resp2.status_code)

asyncio.run(run())
