import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_append = """                sources.append({
                    "url": proxy_url,
                    "isM3U8": "m3u8" in abs_url,
                    "quality": stream.get("quality", "auto")
                })"""

new_append = """                sources.append({
                    "url": proxy_url,
                    "isM3U8": "m3u8" in abs_url,
                    "quality": stream.get("quality", "auto"),
                    "serverName": stream.get("server", "Auto")
                })"""

if old_append in content:
    content = content.replace(old_append, new_append)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed api/source to include serverName!")
else:
    print("Could not find the append logic to fix.")
