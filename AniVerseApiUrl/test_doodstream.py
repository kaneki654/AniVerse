import asyncio
import httpx
import re
import random
import string

async def run():
    url = "https://myvidplay.com/e/k5rhjm2vveg3"
    async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
        # Step 1: Get the Doodstream page
        resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0"})
        print("Status:", resp.status_code)
        
        # Step 2: Find the /pass_md5/ link
        match = re.search(r"(/pass_md5/[^']*)", resp.text)
        if not match:
            print("No pass_md5 found in HTML")
            return
            
        pass_md5_url = "https://myvidplay.com" + match.group(1)
        print("Pass MD5 URL:", pass_md5_url)
        
        # Step 3: Find the token in the HTML
        token_match = re.search(r"token=([^&]+)", pass_md5_url)
        token = match.group(1).split("/")[-1] if not token_match else token_match.group(1)
        
        # Step 4: Make a request to the /pass_md5/ endpoint
        headers = {"User-Agent": "Mozilla/5.0", "Referer": url}
        resp2 = await client.get(pass_md5_url, headers=headers)
        print("Pass MD5 Status:", resp2.status_code)
        
        if resp2.status_code == 200:
            # Step 5: Construct the final URL
            # The response is the base URL. We append a random string + "?token=" + token + "&expiry=" + timestamp
            base_url = resp2.text
            random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
            
            # Need to get the expiry timestamp, usually it's just the current time
            import time
            expiry = str(int(time.time() * 1000))
            
            final_url = f"{base_url}{random_str}?token={token}&expiry={expiry}"
            print("Final Doodstream URL:", final_url)
            
            # Test it
            resp3 = await client.get(final_url, headers=headers)
            print("Final Doodstream Status:", resp3.status_code)
            
asyncio.run(run())
