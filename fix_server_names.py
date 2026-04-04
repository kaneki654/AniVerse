import re

# 1. Update vidsrc.py
with open('AniVerseApiUrl/app/providers/vidsrc.py', 'r') as f:
    content = f.read()

old_vidsrc = 'streams.append({"url": master_url, "quality": "auto"})'
new_vidsrc = 'streams.append({"url": master_url, "quality": "auto", "server": server.get("name", "VidSrc")})'

if old_vidsrc in content:
    content = content.replace(old_vidsrc, new_vidsrc)
    with open('AniVerseApiUrl/app/providers/vidsrc.py', 'w') as f:
        f.write(content)
    print("Fixed vidsrc.py server names!")

# 2. Update gogoanime.py
with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

# Replace VibePlayer stream append
old_vibe = """                    streams.append({
                        "quality": "auto",
                        "url": master_url
                    })"""
new_vibe = """                    streams.append({
                        "quality": "auto",
                        "url": master_url,
                        "server": server.get("name", "VibePlayer")
                    })"""
content = content.replace(old_vibe, new_vibe)

# Replace OtakuHG stream append
old_otaku = """                            streams.append({
                                "quality": "auto",
                                "url": m3u8_links[0]
                            })"""
new_otaku = """                            streams.append({
                                "quality": "auto",
                                "url": m3u8_links[0],
                                "server": server.get("name", "StreamHG")
                            })"""
content = content.replace(old_otaku, new_otaku)

# Replace Doodstream stream append
old_dood = """                                streams.append({
                                    "quality": "auto",
                                    "url": final_url
                                })"""
new_dood = """                                streams.append({
                                    "quality": "auto",
                                    "url": final_url,
                                    "server": server.get("name", "Doodstream")
                                })"""
content = content.replace(old_dood, new_dood)

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
    f.write(content)
print("Fixed gogoanime.py server names!")
