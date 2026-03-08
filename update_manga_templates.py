import re

def patch_home():
    with open('app/templates/manga_home.html', 'r') as f:
        content = f.read()
    
    # Replace cover paths
    content = content.replace('item.cover', 'proxy_base ~ item.image|urlencode')
    content = content.replace('item.desc', 'item.description')
    
    # Replace the browse by genre section
    old_tags = """<section>
    <h2>Browse by Genre</h2>
    <div class="genres">
        {% for tag in tags %}
        <a href="/manga/search?tag={{ tag.id }}">{{ tag.attributes.name.en }}</a>
        {% endfor %}
    </div>
</section>"""
    new_tags = """<section>
    <h2>Recent Additions</h2>
    <div class="grid">
        {% for item in recent %}
        <div class="anime-card">
            <a href="/manga/{{ item.id }}">
                <img src="{{ proxy_base }}{{ item.image|urlencode }}" alt="{{ item.title }}" loading="lazy" referrerpolicy="no-referrer" onerror="this.src='/static/placeholder.jpg'">
                <div class="card-info">
                    <h4>{{ item.title }}</h4>
                </div>
            </a>
        </div>
        {% endfor %}
    </div>
</section>"""
    content = content.replace(old_tags, new_tags)
    
    # Update search param
    content = content.replace('name="title"', 'name="q"')

    with open('app/templates/manga_home.html', 'w') as f:
        f.write(content)

patch_home()

def patch_search():
    with open('app/templates/manga_search.html', 'r') as f:
        content = f.read()
    
    content = content.replace('manga.cover', 'proxy_base ~ manga.image|urlencode')
    content = content.replace('manga.desc', 'manga.description')

    with open('app/templates/manga_search.html', 'w') as f:
        f.write(content)

patch_search()

def patch_detail():
    with open('app/templates/manga_detail.html', 'r') as f:
        content = f.read()

    # Update title
    content = content.replace('manga.title', 'manga.title')
    # Cover image
    content = content.replace('<img src="{{ manga.cover }}"', '<img src="{{ proxy_base }}{{ manga.image|urlencode }}"')
    
    # Status, Author, Year
    content = content.replace('manga.year', 'manga.releaseDate')
    
    # Authors loop
    old_author = '{{ manga.author }}'
    new_author = '{% for author in manga.authors %}{{ author }}{% if not loop.last %}, {% endif %}{% endfor %}'
    content = content.replace(old_author, new_author)

    # Description
    content = content.replace('manga.desc', 'manga.description')
    
    # Genres loop
    old_genres = """{% for tag in manga.tags %}
                <span class="genre">{{ tag }}</span>
                {% endfor %}"""
    new_genres = """{% for genre in manga.genres %}
                <span class="genre">{{ genre }}</span>
                {% endfor %}"""
    content = content.replace(old_genres, new_genres)
    
    # Chapter link
    content = content.replace('/manga/read/{{ chapter.id }}', '/manga/read/{{ manga.id }}/{{ chapter.id }}')
    
    # Chapter fields
    content = content.replace('chapter.chapter', 'chapter.chapterNumber')
    content = content.replace('chapter.title', 'chapter.title')
    content = content.replace('chapter.group', 'chapter.pages ~ " pages"')
    content = content.replace('chapter.date', 'chapter.releaseDate')
    
    with open('app/templates/manga_detail.html', 'w') as f:
        f.write(content)

patch_detail()

def patch_reader():
    with open('app/templates/manga_read.html', 'r') as f:
        content = f.read()
    
    # Images
    content = content.replace('"/proxy/manga-page?url=" + encodeURIComponent(pages[i]) + "&referer=mangadex.org"', '`{{ proxy_base }}${encodeURIComponent(pages[i].img)}`')
    
    # Navigation
    content = content.replace("'/manga/read/{{ prev_chapter }}'", "'/manga/read/{{ manga_id }}/{{ prev_chapter }}'")
    content = content.replace("'/manga/read/{{ next_chapter }}'", "'/manga/read/{{ manga_id }}/{{ next_chapter }}'")
    content = content.replace('{{ next_chapter }}', '{% if next_chapter %}{{ next_chapter }}{% endif %}')
    content = content.replace('{{ prev_chapter }}', '{% if prev_chapter %}{{ prev_chapter }}{% endif %}')

    with open('app/templates/manga_read.html', 'w') as f:
        f.write(content)

patch_reader()
