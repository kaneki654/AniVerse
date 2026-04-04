import asyncio
import httpx
import re
import random
import string
import time

async def run():
    url = "https://myvidplay.com/e/k5rhjm2vveg3"  # Doodstream embed URL for Amagami Sister Dub
    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Step 1: Get the Doodstream page
        resp = await client.get(url, headers=headers)
        print("Doodstream Page Status:", resp.status_code)
        
        # Step 2: Find the /pass_md5/ link
        match = re.search(r"(/pass_md5/[^']*)", resp.text)
        if not match:
            print("No pass_md5 found in HTML")
            # Let's see if it's protected
            if "Cloudflare" in resp.text:
                print("Cloudflare protected")
            return
            
        pass_md5_url = "https://myvidplay.com" + match.group(1)
        print("Pass MD5 URL:", pass_md5_url)
        
        # Step 3: Find the token in the HTML
        # Token is usually in the pass_md5 url or somewhere else
        token = pass_md5_url.split("/")[-1]
        
        # We also need a delay because Doodstream requires it
        await asyncio.sleep(1)
        
        # Step 4: Make a request to the /pass_md5/ endpoint
        headers["Referer"] = url
        resp2 = await client.get(pass_md5_url, headers=headers)
        print("Pass MD5 Status:", resp2.status_code)
        
        if resp2.status_code == 200:
            # Step 5: Construct the final URL
            base_url = resp2.text
            random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
            expiry = str(int(time.time() * 1000))
            
            final_url = f"{base_url}{random_str}?token={token}&expiry={expiry}"
            print("Final Doodstream URL:", final_url)
            
            # Since Doodstream returns a direct mp4, we can test it
            resp3 = await client.head(final_url, headers=headers)
            print("Final Doodstream Status:", resp3.status_code)
            
            if resp3.status_code in [200, 302, 206]:
                print("Success! Doodstream works.")
            else:
                print("Failed.")
                
asyncio.run(run())
