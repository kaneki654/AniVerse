with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_search = r'''matches = re.findall(r'<p class="name"><a href="/category/([^"]+)"', search_resp.text)'''
new_search = r'''matches = re.findall(r'<p class="name">\s*<a href="/category/([^"]+)"', search_resp.text)'''

if old_search in content:
    content = content.replace(old_search, new_search)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed regex properly!")
else:
    print("Could not find regex.")
