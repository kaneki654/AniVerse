import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Fix read endpoint
old_read = """read_resp = await client.get(f"{MANGA_API_BASE}/read?chapterId={chapter_id}")"""
new_read = """read_resp = await client.get(f"{MANGA_API_BASE}/read/{chapter_id}", timeout=15)"""
content = content.replace(old_read, new_read)

with open('app/main.py', 'w') as f:
    f.write(content)
