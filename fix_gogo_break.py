import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_otakuhg_break = """                            if not subtitles and category == "sub":
                                continue
                            break
                except Exception as e:"""

new_otakuhg_break = """                            if not subtitles and category == "sub":
                                continue
                            # Do NOT break for otakuhg/premilkyway because they are Cloudflare IP-locked.
                            # We want to continue scanning servers so we can find Doodstream as a fallback!
                            continue
                except Exception as e:"""

if old_otakuhg_break in content:
    content = content.replace(old_otakuhg_break, new_otakuhg_break)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed OtakuHG extraction to NOT break the loop!")
else:
    print("Could not find the break logic to replace.")
