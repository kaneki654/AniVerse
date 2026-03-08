import re

with open('app/templates/manga_read.html', 'r') as f:
    content = f.read()

# Update pages loop
old_pages_loop = """        {% for page in pages %}
        <img src="{{ page }}" loading="lazy" alt="Page {{ loop.index }}">
        {% endfor %}"""

new_pages_loop = """        {% for page in pages %}
        <img src="{{ proxy_base }}{{ page.img|urlencode }}" loading="lazy" alt="Page {{ page.page }}">
        {% endfor %}"""
content = content.replace(old_pages_loop, new_pages_loop)

# Update nav links
# Previously: /manga/read/{{ prev_id }}
# Now: /manga/read/{{ manga_id }}/{{ prev_chapter }}
content = content.replace('{{ prev_id }}', '{{ manga_id }}/{{ prev_chapter }}')
content = content.replace('{{ next_id }}', '{{ manga_id }}/{{ next_chapter }}')
content = content.replace('{% if prev_id %}', '{% if prev_chapter %}')
content = content.replace('{% if next_id %}', '{% if next_chapter %}')
content = content.replace('info.chapter', 'chapter_info.chapterNumber')
content = content.replace('info.title', 'chapter_info.title')
content = content.replace('info.manga_id', 'manga_id')

with open('app/templates/manga_read.html', 'w') as f:
    f.write(content)
