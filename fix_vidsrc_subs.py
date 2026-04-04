with open('AniVerseApiUrl/app/providers/vidsrc.py', 'r') as f:
    content = f.read()

bad_extract = """                # Extract the M3U8 string from the PlayerJS setup
                m3u8_match = re.search(r'file:\s*"([^"]+)"', resp2.text)
                if m3u8_match:
                    raw_m3u8 = m3u8_match.group(1)
                    
                    # Split out the 'or' fallback streams
                    urls = raw_m3u8.split(" or ")
                    if not urls:
                        continue
                        
                    master_url = urls[0]
                    # Replace the domain placeholder {v1} with the actual host
                    master_url = master_url.replace("{v1}", parsed_url.netloc)
                    
                    # Simply return the master M3U8 so hls.js can parse all qualities natively
                    streams.append({"url": master_url, "quality": "auto"})
                    break # Stop after success"""

good_extract = """                # Extract the M3U8 string from the PlayerJS setup
                m3u8_match = re.search(r'file:\s*"([^"]+)"', resp2.text)
                subtitles = []
                if m3u8_match:
                    raw_m3u8 = m3u8_match.group(1)
                    urls = raw_m3u8.split(" or ")
                    if urls:
                        master_url = urls[0].replace("{v1}", parsed_url.netloc)
                        streams.append({"url": master_url, "quality": "auto"})
                    
                    subs_match = re.search(r'subtitle:\s*"([^"]+)"', resp2.text)
                    if subs_match:
                        raw_subs = subs_match.group(1)
                        for s in raw_subs.split(","):
                            m = re.search(r'\[(.*?)\](.*)', s)
                            if m:
                                subtitles.append({"file": m.group(2), "label": m.group(1), "kind": "captions"})
                    
                    # Return right away with both streams and subtitles
                    return {"streams": streams, "subtitles": subtitles}"""

if bad_extract in content:
    content = content.replace(bad_extract, good_extract)
    with open('AniVerseApiUrl/app/providers/vidsrc.py', 'w') as f:
        f.write(content)
    print("Fixed vidsrc.py to extract subtitles")
else:
    print("Could not find the target string in vidsrc.py")
