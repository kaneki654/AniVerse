import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_search = """            if resp.status_code == 200:
                data = resp.json()
            elif resp.status_code == 400 and genres and not q:
                # Fallback if empty query is rejected but genres are provided
                fallback_url = f"{API_BASE}/search?page={page}&q=a&genres={genres}"
                resp_fallback = await client.get(fallback_url)
                if resp_fallback.status_code == 200:
                    data = resp_fallback.json()"""

new_search = """            if resp.status_code == 200:
                data = resp.json()
            elif resp.status_code == 400 and not q:
                # Fallback if empty query is rejected
                fallback_url = f"{API_BASE}/search?page={page}&q=a"
                if genres:
                    fallback_url += f"&genres={genres}"
                resp_fallback = await client.get(fallback_url)
                if resp_fallback.status_code == 200:
                    data = resp_fallback.json()"""

content = content.replace(old_search, new_search)

with open('app/main.py', 'w') as f:
    f.write(content)
