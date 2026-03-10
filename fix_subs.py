with open('app/static/player.js', 'r') as f:
    content = f.read()

# I will just write a regex to clean up the logic in setupSubtitles and any other place that used to rely on t.label/t.file instead of both.

# Let's replace the properties setup:
# from: const label = t.label || t.label || "Unknown";
# to:   const label = t.label || t.lang || "Unknown";

# from: const url = t.file || t.file;
# to:   const url = t.file || t.url;

import re

content = re.sub(
    r'const label = t\.label \|\| t\.label \|\| "Unknown";',
    'const label = t.label || t.lang || "Unknown";',
    content
)

content = re.sub(
    r'const url = t\.file \|\| t\.file;',
    'const url = t.file || t.url;',
    content
)

content = re.sub(
    r't\.label\.substring',
    '(t.label || t.lang || "en").substring',
    content
)

content = re.sub(
    r'encodeURIComponent\(t\.file\)',
    'encodeURIComponent(t.file || t.url)',
    content
)

content = re.sub(
    r't\.kind === \'thumbnails\' \|\| t\.label === \'Thumbnails\'',
    't.kind === \'thumbnails\' || (t.label || t.lang) === \'Thumbnails\' || (t.label || t.lang) === \'thumbnails\'',
    content
)


# Re-patch the old tracks.forEach inside the older setup logic if it exists (lines 940-960)
# We can just change everything there to use `label` and `url` variables to be safe.
# Actually it's easier to just do simple replacements.
content = re.sub(r'\bt\.label\b', '(t.label || t.lang)', content)
content = re.sub(r'\bt\.file\b', '(t.file || t.url)', content)

# But wait, that might break things if `t` doesn't exist.
# Let's be surgical.

