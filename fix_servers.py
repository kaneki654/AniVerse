import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# I want to check how the "Quality" or "Source" menu is built.
# I'll just print out a slice around the menu population.
match = re.search(r'updateQualityOptions.*?\{', content, re.DOTALL)
if match:
    start_idx = match.start()
    print(content[start_idx:start_idx+1000])

