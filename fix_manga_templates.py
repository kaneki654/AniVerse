with open('app/templates/manga_home.html', 'r') as f:
    content = f.read()
content = content.replace('{{ proxy_base ~ item.image|urlencode }}', '{{ proxy_base }}{{ item.image|urlencode }}')
with open('app/templates/manga_home.html', 'w') as f:
    f.write(content)

with open('app/templates/manga_search.html', 'r') as f:
    content = f.read()
content = content.replace('{{ proxy_base ~ manga.image|urlencode }}', '{{ proxy_base }}{{ manga.image|urlencode }}')
with open('app/templates/manga_search.html', 'w') as f:
    f.write(content)
