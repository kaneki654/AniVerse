import asyncio
import httpx
import re

def unpack(p, a, c, k, e, d):
    while c:
        c -= 1
        if k[c]:
            p = re.sub('\\b' + str(c) if a <= 36 else '[0-9a-zA-Z]+', k[c], p) # Wait, unpacking logic requires correct base conversion.
    return p

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://otakuhg.site/e/cjqev3hl9rif")
        
        # We can just look for the m3u8 URL in the unpacked string
        # Actually, let's just use regex to find all URLs in the packed string's k array
        match = re.search(r'return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        if match:
            k = match.group(4).split('|')
            print("Words:", [w for w in k if 'm3u8' in w or 'http' in w or '.site' in w or 'shop' in w])
            # Let's print the whole array
            # print(k)
        
asyncio.run(main())
