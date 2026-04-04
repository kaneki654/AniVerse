import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

# I want to add doodstream extraction logic at the end of the loop, but before the return statement.
doodstream_logic = """
            elif "dood" in server["url"] or "vidplay" in server["url"]:
                try:
                    embed_url = server["url"]
                    import random
                    import string
                    import time
                    import asyncio
                    
                    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
                    r = await client.get(embed_url, headers=headers)
                    if r.status_code == 200:
                        match = re.search(r"(/pass_md5/[^']*)", r.text)
                        if match:
                            pass_md5_url = "https://" + urllib.parse.urlparse(embed_url).netloc + match.group(1)
                            token = pass_md5_url.split("/")[-1]
                            
                            await asyncio.sleep(1) # Bypass doodstream simple ratelimit
                            r2 = await client.get(pass_md5_url, headers={"User-Agent": headers["User-Agent"], "Referer": embed_url})
                            
                            if r2.status_code == 200:
                                base_url = r2.text
                                random_str = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
                                expiry = str(int(time.time() * 1000))
                                final_url = f"{base_url}{random_str}?token={token}&expiry={expiry}"
                                
                                streams.append({
                                    "quality": "auto",
                                    "url": final_url
                                })
                                break # Doodstream worked
                except Exception as e:
                    print(f"Doodstream Extraction Failed: {e}")
                    continue
"""

# Locate the end of the OtakuHG elif block.
end_of_otakuhg = """                    print(f"OtakuHG Extraction Failed: {e}")
                    continue"""

if end_of_otakuhg in content and doodstream_logic not in content:
    new_content = content.replace(end_of_otakuhg, end_of_otakuhg + "\n" + doodstream_logic)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(new_content)
    print("Doodstream logic added successfully.")
else:
    print("Could not find the injection point or logic already exists.")
