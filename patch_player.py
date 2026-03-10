import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# Replace t.lang with t.label
content = re.sub(r'\bt\.lang\b', 't.label', content)

# Replace t.url with t.file
content = re.sub(r'\bt\.url\b', 't.file', content)

with open('app/static/player.js', 'w') as f:
    f.write(content)

print("Patched player.js")
