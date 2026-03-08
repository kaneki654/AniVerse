with open('app/templates/manga_read.html', 'r') as f:
    content = f.read()

# Make the title fallback a bit cleaner. If chapter.title is null, the previous code might have printed 'None'
old_title_logic = """{% if chapter_info.chapterNumber and chapter_info.chapterNumber != 'None' %}Ch. {{ chapter_info.chapterNumber }}{% else %}Oneshot{% endif %}
                {% if chapter_info.title and chapter_info.title != 'None' %} - {{ chapter_info.title or "" }}{% endif %}"""

new_title_logic = """{% if chapter_info.chapterNumber and chapter_info.chapterNumber != 'None' %}Ch. {{ chapter_info.chapterNumber }}{% else %}Oneshot{% endif %}
                {% if chapter_info.title and chapter_info.title != 'None' %} - {{ chapter_info.title }}{% endif %}"""

content = content.replace(old_title_logic, new_title_logic)

with open('app/templates/manga_read.html', 'w') as f:
    f.write(content)
