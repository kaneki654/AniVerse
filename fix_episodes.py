import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Replace the problematic line
bad_line = 'data["data"]["latestEpisodeAnimes"][idx]["episodes"] = {"sub": item.get("episodes") or "?"}'
good_line = 'data["data"]["latestEpisodeAnimes"][idx]["episodes"] = item.get("episodes")'

content = content.replace(bad_line, good_line)

with open('app/main.py', 'w') as f:
    f.write(content)
print("Fixed episode badge bug")
