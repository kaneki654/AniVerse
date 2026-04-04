with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_subs = '''                    # Extract subtitle from query params
                    params = urllib.parse.parse_qs(parsed.query)
                    subs = params.get('sub', [])
                    if subs:
                        subtitles.append({
                            "file": subs[0],
                            "label": "English",
                            "kind": "captions"
                        })'''

new_subs = '''                    # Extract subtitle from query params
                    params = urllib.parse.parse_qs(parsed.query)
                    subs = params.get('sub', [])
                    if subs:
                        subtitles.append({
                            "file": subs[0],
                            "label": "English",
                            "kind": "captions"
                        })
                        
                    # Also try to extract multiple captions from caption_1, caption_2 etc
                    for key, val in params.items():
                        if key.startswith('caption_'):
                            idx = key.split('_')[1]
                            lang = params.get(f'sub_{idx}', ['English'])[0]
                            subtitles.append({
                                "file": val[0],
                                "label": lang,
                                "kind": "captions"
                            })'''

if old_subs in content:
    content = content.replace(old_subs, new_subs)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime extraction to find more subtitles!")
else:
    print("Could not find the extraction logic to fix.")
