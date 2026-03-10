import re

with open('app/main.py', 'r') as f:
    content = f.read()

# 1. Change the base URL variable
content = re.sub(
    r'API_BASE\s*=\s*"https://aniverseaniwatch\.vercel\.app/api/v2/hianime"',
    'API_BASE = "https://aniwatch-api-production-7717.up.railway.app"',
    content
)

# Replace all occurrences of `{API_BASE}/` with `{API_BASE}/api/v2/hianime/`
content = content.replace('{API_BASE}/', '{API_BASE}/api/v2/hianime/')

# Special fix for suggestion -> suggest (from Step 2: Search suggestions call — change /anime/search/suggest to /api/v2/hianime/search/suggest)
content = content.replace('{API_BASE}/api/v2/hianime/search/suggestion', '{API_BASE}/api/v2/hianime/search/suggest')

with open('app/main.py', 'w') as f:
    f.write(content)

print("Patched main.py")
