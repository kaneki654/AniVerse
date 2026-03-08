import re

# Fix app/templates/manga_read.html
html_path = 'app/templates/manga_read.html'
with open(html_path, 'r') as f:
    html_content = f.read()

# Fix the title block
html_content = re.sub(
    r'{%\s*block title\s*%}.*?{%\s*endblock\s*%}',
    r'{% block title %}Reading {{ chapter_info.title or "Chapter" }}{% endblock %}',
    html_content,
    flags=re.DOTALL
)

# Fix the chapter label
# Currently it might look like: {% if chapter_info.chapterNumber and chapter_info.chapterNumber != 'None' %}Ch. {{ chapter_info.chapterNumber }}{% else %}Oneshot{% endif %}
html_content = re.sub(
    r'{%\s*if chapter_info\.chapterNumber.*?endif\s*%}',
    r'Ch. {{ chapter_info.chapterNumber or "Oneshot" }}',
    html_content,
    flags=re.DOTALL
)

with open(html_path, 'w') as f:
    f.write(html_content)


# Fix app/main.py
py_path = 'app/main.py'
with open(py_path, 'r') as f:
    py_content = f.read()

# Fix the pages loop for proxy wrapping
old_loop = """                for page in pages:
                    if "img" in page:
                        safe_url = quote(page["img"], safe='')
                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={safe_url}"
"""
new_loop = """                for page in pages:
                    if page.get("img"):
                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page['img'], safe='')}"
"""

# Wait, if old_loop is exactly matched, it works. Let's make it robust by using regex.
py_content = re.sub(
    r'for\s+page\s+in\s+pages:\s+if\s+"img"\s+in\s+page:\s+safe_url\s*=\s*quote\(page\["img"\],\s*safe=\'\'\)\s+page\["img"\]\s*=\s*f"https://consumet-swart-nine\.vercel\.app/manga/mangadex/proxy\?url=\{safe_url\}"',
    r'for page in pages:\n                    if page.get("img"):\n                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page[\'img\'], safe=\'\')}"',
    py_content
)

# Or safer replacement:
py_content = py_content.replace(
    '                for page in pages:\n                    if "img" in page:\n                        safe_url = quote(page["img"], safe=\'\')\n                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={safe_url}"',
    '                for page in pages:\n                    if page.get("img"):\n                        page["img"] = f"https://consumet-swart-nine.vercel.app/manga/mangadex/proxy?url={quote(page[\'img\'], safe=\'\')}"'
)

# Fix the navigation API call
# Currently: info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id.strip('/')}", timeout=30)
py_content = py_content.replace(
    'info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id.strip(\'/\')}", timeout=30)',
    'info_resp = await client.get(f"{MANGA_API_BASE}/info/{manga_id}", timeout=30)'
)

with open(py_path, 'w') as f:
    f.write(py_content)

print("Done fixing files.")
