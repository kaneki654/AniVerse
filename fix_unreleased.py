import re

# 1. Update app/main.py to include status in anime_info
with open('app/main.py', 'r') as f:
    content = f.read()

old_stats = """            anime_info = {
                "name": title,
                "poster": media["coverImage"]["large"],
                "description": media.get("description", "No description available."),
                "stats": {
                    "rating": f"{media.get('averageScore', 'N/A')}/100",
                    "quality": "HD",
                    "episodes": {"sub": ep_count, "dub": 0},
                    "type": "TV"
                }
            }"""

new_stats = """            anime_info = {
                "name": title,
                "poster": media["coverImage"]["large"],
                "description": media.get("description", "No description available."),
                "stats": {
                    "rating": f"{media.get('averageScore', 'N/A')}/100",
                    "quality": "HD",
                    "episodes": {"sub": ep_count, "dub": 0},
                    "type": "TV",
                    "status": media.get("status", "FINISHED")
                }
            }"""

if old_stats in content:
    content = content.replace(old_stats, new_stats)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Updated main.py to include anime status!")
else:
    print("Could not find the anime_info stats block in main.py")

# 2. Update app/templates/detail.html
with open('app/templates/detail.html', 'r') as f:
    html_content = f.read()

old_actions = """            <div class="actions">
                <a href="#episodes" class="btn-watch">Watch Now</a>
            </div>"""

new_actions = """            <div class="actions">
                {% if anime.info.stats.status == "NOT_YET_RELEASED" %}
                <div class="btn-watch" style="background: #555; cursor: not-allowed;">This Anime Hasn't been release yet</div>
                {% else %}
                <a href="#episodes" class="btn-watch">Watch Now</a>
                {% endif %}
            </div>"""

if old_actions in html_content:
    html_content = html_content.replace(old_actions, new_actions)

old_episodes = """    <div id="episodes" class="episodes-section">
        <h2>Episodes</h2>
        <div class="episodes-grid">
            {% for episode in episodes %}
            <a href="/watch/{{ episode.episodeId }}" class="episode-card {% if episode.isFiller %}filler{% endif %}">
                <div class="ep-number">{{ episode.number }}</div>
                <div class="ep-title">{{ episode.title }}</div>
            </a>
            {% endfor %}
        </div>
    </div>"""

new_episodes = """    {% if anime.info.stats.status != "NOT_YET_RELEASED" %}
    <div id="episodes" class="episodes-section">
        <h2>Episodes</h2>
        <div class="episodes-grid">
            {% for episode in episodes %}
            <a href="/watch/{{ episode.episodeId }}" class="episode-card {% if episode.isFiller %}filler{% endif %}">
                <div class="ep-number">{{ episode.number }}</div>
                <div class="ep-title">{{ episode.title }}</div>
            </a>
            {% endfor %}
        </div>
    </div>
    {% endif %}"""

if old_episodes in html_content:
    html_content = html_content.replace(old_episodes, new_episodes)

with open('app/templates/detail.html', 'w') as f:
    f.write(html_content)
print("Updated detail.html!")
