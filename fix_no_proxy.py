import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_source = """                if "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url"""

new_source = """                # Do NOT proxy premilkyway.com streams because they use tokenized IPs/Cookies
                if "premilkyway.com" in abs_url:
                    proxy_url = abs_url
                elif "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url"""

if old_source in content:
    content = content.replace(old_source, new_source)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed api/source to NOT proxy premilkyway streams!")
else:
    print("Could not find the proxy logic to replace.")
