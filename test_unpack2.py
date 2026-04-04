import asyncio
import httpx
import re

def unpack(p, a, c, k, e, d):
    # e is the base conversion function
    def e(c):
        return (str(c) if c < a else e(c // a)) if a <= 36 else \
               (chr(c + 29) if c >= 36 else str(c)) # simplified, maybe not perfectly matching JS but good enough
               
    # actually Python doesn't have base36 builtin like JS toString(36)
    def to_base(num, base):
        if num == 0: return '0'
        res = ""
        while num > 0:
            rem = num % base
            res = (str(rem) if rem < 10 else chr(rem - 10 + ord('a'))) + res
            num //= base
        return res

    while c > 0:
        c -= 1
        if k[c]:
            word = to_base(c, a)
            # escape word for regex if needed, but it's alphanumeric
            p = re.sub(r'\b' + word + r'\b', k[c], p)
    return p

async def main():
    async with httpx.AsyncClient() as client:
        r = await client.get("https://otakuhg.site/e/cjqev3hl9rif")
        match = re.search(r'eval\(function\(p,a,c,k,e,d\).*?return p}\(\'(.*?)\',(\d+),(\d+),\'(.*?)\'\.split', r.text)
        if match:
            p = match.group(1).replace('\\\'', "'") # wait, the original regex didn't handle escapes perfectly
            a = int(match.group(2))
            c = int(match.group(3))
            k = match.group(4).split('|')
            
            unpacked = unpack(p, a, c, k, None, None)
            # print(unpacked)
            
            # Find m3u8
            m = re.findall(r'https?://[^"\']+\.m3u8', unpacked)
            print("Found m3u8s:", m)

asyncio.run(main())
