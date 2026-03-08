with open('app/main.py', 'r') as f:
    content = f.read()

old_code = """                if "image" in manga_info:
                    manga_info["image"] = fix_cover(manga_info["image"])"""

new_code = """                if not manga_info.get("title"):
                    alt_titles = manga_info.get("altTitles", [])
                    fallback = "Unknown Title"
                    for alt in alt_titles:
                        if isinstance(alt, dict):
                            if "en" in alt:
                                fallback = alt["en"]
                                break
                            elif alt:
                                fallback = list(alt.values())[0]
                    manga_info["title"] = fallback

                if "image" in manga_info:
                    manga_info["image"] = fix_cover(manga_info["image"])"""

content = content.replace(old_code, new_code)
with open('app/main.py', 'w') as f:
    f.write(content)
