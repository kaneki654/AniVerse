import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# Fix the override setupSubtitles
content = content.replace(
    'const label = (t.label || t.lang) || (t.label || t.lang) || "Unknown";',
    'const label = t.label || t.lang || "Unknown";'
)
content = content.replace(
    'const label = t.label || t.label || "Unknown";',
    'const label = t.label || t.lang || "Unknown";'
)

content = content.replace(
    'const url = (t.file || t.url) || (t.file || t.url);',
    'const url = t.file || t.url;'
)
content = content.replace(
    'const url = t.file || t.file;',
    'const url = t.file || t.url;'
)

content = content.replace(
    'track.srclang = (t.label || t.lang).substring(0, 2).toLowerCase();',
    'track.srclang = (t.label || t.lang || "en").substring(0, 2).toLowerCase();'
)

content = content.replace(
    'track.src = `/proxy/subtitle?url=${encodeURIComponent((t.file || t.url))}&referer=${encodeURIComponent(referer)}`;',
    'track.src = `/proxy/subtitle?url=${encodeURIComponent(t.file || t.url)}&referer=${encodeURIComponent(referer)}`;'
)
content = content.replace(
    'track.src = `/proxy/subtitle?url=${encodeURIComponent(t.file)}&referer=${encodeURIComponent(referer)}`;',
    'track.src = `/proxy/subtitle?url=${encodeURIComponent(t.file || t.url)}&referer=${encodeURIComponent(referer)}`;'
)

content = content.replace(
    "if (t.kind === 'thumbnails' || t.label === 'Thumbnails') return;",
    "if (t.kind === 'thumbnails' || (t.label || t.lang) === 'Thumbnails' || (t.label || t.lang) === 'thumbnails') return;"
)
content = content.replace(
    "track.label = t.label;",
    "track.label = t.label || t.lang || 'Unknown';"
)
content = content.replace(
    "item.onclick = () => this.setSubtitle(t.label);",
    "item.onclick = () => this.setSubtitle(t.label || t.lang);"
)
content = content.replace(
    "<span>${t.label}</span>",
    "<span>${t.label || t.lang}</span>"
)

with open('app/static/player.js', 'w') as f:
    f.write(content)
