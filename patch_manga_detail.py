import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_detail = """        try:
            resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=15)
            print(f"Detail API Status: {resp.status_code}")
            print(f"Detail API Response (first 500 chars): {resp.text[:500]}")
            import sys; sys.stdout.flush()
            if resp.status_code == 200:"""

new_detail = """        try:
            url = f"{MANGA_API_BASE}/info/{manga_id}"
            print(f"CALLING: {url}")
            import sys; sys.stdout.flush()
            resp = await client.get(url, timeout=30)
            print(f"STATUS: {resp.status_code}")
            print(f"BODY: {resp.text[:200]}")
            sys.stdout.flush()
            if resp.status_code == 200:"""

content = content.replace(old_detail, new_detail)

old_error = """        except Exception as e:
            print(f"Manga Detail Error: {e}")"""

new_error = """        except Exception as e:
            print(f"Manga Detail ERROR: {str(e)}")
            import sys; sys.stdout.flush()"""

content = content.replace(old_error, new_error)

with open('app/main.py', 'w') as f:
    f.write(content)
