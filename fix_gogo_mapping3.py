import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_mapping = '''                    else:
                        # Fallback to search using explicit DUB keyword
                        search_url2 = f"{self.base_url}/search.html?keyword={urllib.parse.quote(title + ' dub')}"
                        search_resp2 = await client.get(search_url2, headers={"User-Agent": "Mozilla/5.0"})
                        matches2 = re.findall(r'href="/category/([^"]+)"', search_resp2.text)
                        if matches2:
                            return matches2[0]
                        # Final fallback: use romaji title to create slug
                        title_ro = data.get("title", {}).get("romaji")
                        if title_ro:
                            import re
                            def slugify(text):
                                return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
                            return slugify(title_ro) + "-dub"
                        return slug + "-dub"'''

new_mapping = '''                    else:
                        # Fallback to search using explicit DUB keyword
                        search_url2 = f"{self.base_url}/search.html?keyword={urllib.parse.quote(title + ' dub')}"
                        search_resp2 = await client.get(search_url2, headers={"User-Agent": "Mozilla/5.0"})
                        matches2 = list(dict.fromkeys(re.findall(r'href="/category/([^"]+)"', search_resp2.text)))
                        if matches2:
                            return matches2[0]
                            
                        # Final fallback: just use the base slug and append '-dub'
                        if not slug.endswith("-dub"):
                            return slug + "-dub"
                        return slug'''

if old_mapping in content:
    content = content.replace(old_mapping, new_mapping)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime mapping to cleanly append -dub to the exact slug we found!")
else:
    print("Could not find the mapping logic to fix.")
