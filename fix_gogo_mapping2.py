with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

import re

old_mapping = '''                if category == "dub":
                    dub_slug = next((m for m in matches if "dub" in m.lower()), None)
                    if dub_slug:
                        return dub_slug
                    else:
                        return slug + "-dub"'''

new_mapping = '''                if category == "dub":
                    dub_slug = next((m for m in matches if "dub" in m.lower()), None)
                    if dub_slug:
                        return dub_slug
                    else:
                        # Fallback to search using explicit DUB keyword
                        search_url2 = f"{self.base_url}/search.html?keyword={urllib.parse.quote(title + ' dub')}"
                        search_resp2 = await client.get(search_url2, headers={"User-Agent": "Mozilla/5.0"})
                        matches2 = re.findall(r'href="/category/([^"]+)"', search_resp2.text)
                        if matches2:
                            return matches2[0]
                        return slug + "-dub"'''

if old_mapping in content:
    content = content.replace(old_mapping, new_mapping)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime mapping to explicitly search for DUBs!")
else:
    print("Could not find the mapping logic to fix.")
