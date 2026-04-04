import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_ref = """                # Fix Referer specifically for StreamHG / premilkyway streams
                if "premilkyway.com" in abs_url:
                    referer = "https://otakuhg.site/"
                elif "vibeplayer.site" in abs_url:
                    referer = "https://vibeplayer.site/\""""

new_ref = """                # Fix Referer specifically for StreamHG / premilkyway streams
                if "premilkyway.com" in abs_url:
                    referer = "https://otakuhg.site/"
                elif "vibeplayer.site" in abs_url:
                    referer = "https://vibeplayer.site/"
                elif "cloudatacdn" in abs_url or "dood" in abs_url:
                    referer = "https://myvidplay.com/\""""

if old_ref in content:
    content = content.replace(old_ref, new_ref)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed Doodstream referer in get_source!")
else:
    print("Could not find the referer logic.")
