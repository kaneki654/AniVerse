with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_ua = 'headers={"User-Agent": "Mozilla/5.0"}'
new_ua = 'headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}'

if old_ua in content:
    content = content.replace(old_ua, new_ua)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed User-Agent in GogoanimeProvider to match the proxy!")
else:
    print("Could not find User-Agent string to fix.")
