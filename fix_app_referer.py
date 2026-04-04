import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_source = """            for stream in data.get("streams", []):
                # Always proxy the master m3u8 to bypass IP-locked streams like premilkyway.com
                abs_url = stream["url"]
                referer = data.get("headers", {}).get("Referer", "https://cloudnestra.com/")
                if "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url"""

new_source = """            for stream in data.get("streams", []):
                # Always proxy the master m3u8 to bypass IP-locked streams like premilkyway.com
                abs_url = stream["url"]
                referer = data.get("headers", {}).get("Referer", "https://cloudnestra.com/")
                
                # Fix Referer specifically for StreamHG / premilkyway streams
                if "premilkyway.com" in abs_url:
                    referer = "https://otakuhg.site/"
                elif "vibeplayer.site" in abs_url:
                    referer = "https://vibeplayer.site/"
                    
                if "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url"""

if old_source in content:
    content = content.replace(old_source, new_source)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed api/source to proxy the correct referer for StreamHG!")
else:
    print("Could not find the source loop.")
