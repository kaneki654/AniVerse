import re

with open('AniVerseApiUrl/app/providers/vidsrc.py', 'r') as f:
    content = f.read()

# Let's see how vidsrc.py extracts subtitles
old_subs = '''                    subs_match = re.search(r'subtitle:\\s*"([^"]+)"', resp2.text)
                    if subs_match:
                        raw_subs = subs_match.group(1)
                        for s in raw_subs.split(","):
                            m = re.search(r'\\[(.*?)\\](.*)', s)
                            if m:
                                subtitles.append({"file": m.group(2), "label": m.group(1), "kind": "captions"})
                    
                    # Return right away with both streams and subtitles
                    return {"streams": streams, "subtitles": subtitles}'''

new_subs = '''                    subs_match = re.search(r'subtitle:\\s*"([^"]+)"', resp2.text)
                    if subs_match:
                        raw_subs = subs_match.group(1)
                        for s in raw_subs.split(","):
                            m = re.search(r'\\[(.*?)\\](.*)', s)
                            if m:
                                subtitles.append({"file": m.group(2), "label": m.group(1), "kind": "captions"})
                    
                    # Also fallback: if no subs found in setup, we can fetch OpenSubtitles or Aniskip etc here, but for now we rely on the provider.
                    # Keep looking through servers if we haven't found subtitles
                    if not subtitles:
                        continue
                        
                    # Return right away with both streams and subtitles
                    return {"streams": streams, "subtitles": subtitles}'''

if old_subs in content:
    content = content.replace(old_subs, new_subs)
    with open('AniVerseApiUrl/app/providers/vidsrc.py', 'w') as f:
        f.write(content)
    print("Fixed VidSrc to keep searching for subtitles!")
else:
    print("Could not find the extraction logic to fix.")
