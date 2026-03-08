with open('app/main.py', 'r') as f:
    content = f.read()

# Add a strip to manga_id and chapter_id to be ultra safe
content = content.replace('url = f"{MANGA_API_BASE}/info/{manga_id}"', 'url = f"{MANGA_API_BASE}/info/{manga_id.strip(\'/\')}"')
content = content.replace('read_resp = await client.get(f"{MANGA_API_BASE}/read/{chapter_id}", timeout=30)', 'read_resp = await client.get(f"{MANGA_API_BASE}/read/{chapter_id.strip(\'/\')}", timeout=30)')
content = content.replace('info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=30)', 'info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id.strip(\'/\')}", timeout=30)')

with open('app/main.py', 'w') as f:
    f.write(content)
