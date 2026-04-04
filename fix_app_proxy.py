import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_source = """            for stream in data.get("streams", []):
                sources.append({
                    "url": stream["url"],
                    "isM3U8": "m3u8" in stream["url"],
                    "quality": stream.get("quality", "auto")
                })"""

new_source = """            for stream in data.get("streams", []):
                # Always proxy the master m3u8 to bypass IP-locked streams like premilkyway.com
                abs_url = stream["url"]
                referer = data.get("headers", {}).get("Referer", "https://cloudnestra.com/")
                if "m3u8" in abs_url:
                    proxy_url = f"/proxy/m3u8?url={quote(abs_url, safe='')}&referer={quote(referer, safe='')}"
                else:
                    proxy_url = abs_url
                    
                sources.append({
                    "url": proxy_url,
                    "isM3U8": "m3u8" in abs_url,
                    "quality": stream.get("quality", "auto")
                })"""

if old_source in content:
    content = content.replace(old_source, new_source)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed api/source to proxy the master m3u8!")
else:
    print("Could not find the source loop.")
