import asyncio
import httpx

async def run():
    url = "https://otakuvid.online/embed/an4kupuhsv8o"
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        print(resp.status_code)
        
        for line in resp.text.split("\n"):
            if "m3u8" in line.lower() or "file" in line.lower() or "source" in line.lower():
                print(line.strip()[:200])
                
        print("---")
        # Check if there's any eval
        import re
        match = re.search(r'eval\(function', resp.text)
        if match:
            print("Found eval!")
            eval_block = re.search(r'eval\(function.*?split\(\'\|\'\)\)\)', resp.text)
            if eval_block:
                print("Eval block preview:", eval_block.group(0)[:100])

asyncio.run(run())
