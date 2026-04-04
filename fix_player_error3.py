import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

old_cache_check = """            if (!this._cachedSources || this._cachedCategory !== category) {
                const url = `/api/source?episode_id=${this.episodeId}&server=Auto&category=${category}`;"""

new_cache_check = """            // We want to force a fetch if the API previously threw an error
            if (!this._cachedSources || this._cachedSources.length === 0 || this._cachedCategory !== category) {
                const url = `/api/source?episode_id=${this.episodeId}&server=Auto&category=${category}`;"""

if old_cache_check in content:
    content = content.replace(old_cache_check, new_cache_check)
    with open('app/static/player.js', 'w') as f:
        f.write(content)
    print("Fixed robust cache check in loadSource!")
else:
    print("Could not find the cache check logic.")
