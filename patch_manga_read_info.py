import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_read_info = """            # Get info for navigation
            info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=15)
            if info_resp.status_code == 200:"""

new_read_info = """            # Get info for navigation
            info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=30)
            if info_resp.status_code == 200:"""

content = content.replace(old_read_info, new_read_info)

with open('app/main.py', 'w') as f:
    f.write(content)
