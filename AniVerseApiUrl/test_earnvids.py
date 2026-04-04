import asyncio
import httpx
import re
from app.providers.gogoanime import GogoAnimeProvider

async def run():
    p = GogoAnimeProvider()
    UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Fetch Amagami Sister dub
        ep = await p.get_episode(client, 'tying-the-knot-with-an-amagami-sister', 1)
        servers = await p.get_servers(client, ep, category='dub')
        
        earnvids_url = None
        for s in servers:
            if 'otakuvid' in s['url'] or 'earnvids' in s['name'].lower():
                earnvids_url = s['url']
                break
                
        if not earnvids_url:
            print("No earnvids url found")
            return
            
        print("Earnvids URL:", earnvids_url)
        r = await client.get(earnvids_url, headers={"User-Agent": UA, "Referer": "https://anitaku.to/"})
        print("Earnvids Status:", r.status_code)
        
        # Look for eval
        match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        if match:
            pv = match.group(1).replace('\\\'', "'")
            av = int(match.group(2))
            cv = int(match.group(3))
            kv = match.group(4).split('|')
            unpacked = p.unpack(pv, av, cv, kv)
            m3u8_links = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
            print("Earnvids Extracted M3U8:", m3u8_links)
        else:
            print("No eval found in Earnvids HTML. Snippet:")
            print(r.text[:500])
            if 'File is no longer available' in r.text:
                print("File deleted.")

asyncio.run(run())
