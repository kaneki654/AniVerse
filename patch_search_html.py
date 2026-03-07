with open('app/templates/search.html', 'r') as f:
    content = f.read()

# Replace the loop over genres
old_loop = """            {% for genre in all_genres %}
                {% set is_selected = genre in selected_genres %}
                
                {# Construct new query string for this genre #}
                {% if is_selected %}
                    {% set new_genres = selected_genres | reject("equalto", genre) | list %}
                {% else %}
                    {% set new_genres = selected_genres + [genre] %}
                {% endif %}
                
                {% set query_string = new_genres|join(',') %}
                
                {# Keep query param if it exists #}
                {% set search_param = '' %}
                {% if query %}
                    {% set search_param = '&q=' ~ query %}
                {% endif %}

                {% set link = '/search?genres=' ~ query_string|urlencode ~ search_param %}
                {% if new_genres|length == 0 %}
                    {% set link = '/search?q=' ~ query if query else '/search' %}
                {% endif %}
                
                <a href="{{ link }}" 
                   class="genre-pill {{ 'selected' if is_selected else '' }}">
                    {{ genre }}
                    {% if is_selected %}<span style="margin-left: 5px;">✓</span>{% endif %}
                </a>
            {% endfor %}"""

new_loop = """            {% for slug, name in all_genres.items() %}
                {% set is_selected = slug in selected_genres %}
                
                {# Construct new query string for this genre using slugs #}
                {% if is_selected %}
                    {% set new_genres = selected_genres | reject("equalto", slug) | list %}
                {% else %}
                    {% set new_genres = selected_genres + [slug] %}
                {% endif %}
                
                {% set query_string = new_genres|join(',') %}
                
                {# Keep query param if it exists #}
                {% set search_param = '' %}
                {% if query %}
                    {% set search_param = '&q=' ~ query %}
                {% endif %}

                {% set link = '/search?genres=' ~ query_string|urlencode ~ search_param %}
                {% if new_genres|length == 0 %}
                    {% set link = '/search?q=' ~ query if query else '/search' %}
                {% endif %}
                
                <a href="{{ link }}" 
                   class="genre-pill {{ 'selected' if is_selected else '' }}">
                    {{ name }}
                    {% if is_selected %}<span style="margin-left: 5px;">✓</span>{% endif %}
                </a>
            {% endfor %}"""

content = content.replace(old_loop, new_loop)

# Also fix the "Showing results for: Action + Romance"
old_show = """            <span class="selected-genres-text">
                Showing results for: 
                {% for g in selected_genres %}
                    <span style="color: #e50000; font-weight: bold;">{{ g }}</span>{% if not loop.last %} + {% endif %}
                {% endfor %}
            </span>"""

new_show = """            <span class="selected-genres-text">
                Showing anime with ALL selected genres: 
                {% for g in selected_genres %}
                    <span style="color: #e50000; font-weight: bold;">{{ all_genres.get(g, g) }}</span>{% if not loop.last %} + {% endif %}
                {% endfor %}
            </span>"""

content = content.replace(old_show, new_show)

with open('app/templates/search.html', 'w') as f:
    f.write(content)
