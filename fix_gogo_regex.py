with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

import re

old_extract = '''            # 3. Parse first result
            matches = re.findall(r'<p class="name">\\s*<a href="/category/([^"]+)"', search_resp.text)'''

new_extract = '''            # 3. Parse first result
            matches = re.findall(r'href="/category/([^"]+)"', search_resp.text)
            matches = list(dict.fromkeys(matches)) # Remove duplicates'''

if old_extract in content:
    content = content.replace(old_extract, new_extract)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime extraction logic!")
else:
    print("Could not find the extraction logic to fix.")
