import re

with open('AniVerseApiUrl/app/services/anilist.py', 'r') as f:
    content = f.read()

# Fix the duplicate 'episodes' caused by the previous replace query
old_dup = "              nextAiringEpisode { episode }\n              episodes"
new_dup = "              nextAiringEpisode { episode }"
content = content.replace(old_dup, new_dup)

with open('AniVerseApiUrl/app/services/anilist.py', 'w') as f:
    f.write(content)
print("Fixed duplicate episodes in AniList query.")
