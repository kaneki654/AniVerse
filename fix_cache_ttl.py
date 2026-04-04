import re

with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

if "ttl_seconds=3600" in content:
    content = content.replace("ttl_seconds=3600", "ttl_seconds=600")
    with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
        f.write(content)
    print("Fixed cache TTL to 10 minutes!")
else:
    print("Could not find ttl_seconds=3600 in orchestrator.py")
