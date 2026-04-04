import re

with open("/home/kerby0818/app/AniVerse/AniVerseApiUrl/app/providers/gogoanime.py", "r") as f:
    content = f.read()

def slugify(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')

replacement = """
                        if matches2:
                            return matches2[0]
                        # Final fallback: use romaji title to create slug
                        title_ro = data.get("title", {}).get("romaji")
                        if title_ro:
                            import re
                            def slugify(text):
                                return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
                            return slugify(title_ro) + "-dub"
                        return slug + "-dub"
"""

content = content.replace("""
                        if matches2:
                            return matches2[0]
                        return slug + "-dub"
""", replacement)

with open("/home/kerby0818/app/AniVerse/AniVerseApiUrl/app/providers/gogoanime.py", "w") as f:
    f.write(content)
