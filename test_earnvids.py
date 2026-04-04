import asyncio
import httpx
import re

def to_base(num, base):
    if num == 0: return '0'
    res = ""
    while num > 0:
        rem = num % base
        res = (str(rem) if rem < 10 else chr(rem - 10 + ord('a'))) + res
        num //= base
    return res

def unpack(p, a, c, k):
    while c > 0:
        c -= 1
        if k[c]:
            word = to_base(c, a)
            p = re.sub(r'\b' + word + r'\b', k[c], p)
    return p

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://otakuvid.online/embed/au391194gj4j")
        match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        if match:
            p = match.group(1).replace('\\\'', "'")
            a = int(match.group(2))
            c = int(match.group(3))
            k = match.group(4).split('|')
            unpacked = unpack(p, a, c, k)
            m = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
            print("Earnvids m3u8s:", m)

asyncio.run(main())
