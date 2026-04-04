import re

with open('app/templates/watch.html', 'r') as f:
    content = f.read()

# Make sure we actually load the v=4 player.js so the user's browser updates again
content = content.replace("player.js?v=3", "player.js?v=4")

with open('app/templates/watch.html', 'w') as f:
    f.write(content)
print("Updated player version to v4!")
