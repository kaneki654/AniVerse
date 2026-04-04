with open('AniVerseApiUrl/app/providers/vidsrc.py', 'r') as f:
    content = f.read()

bad_code = """                    # Now fetch the master playlist to parse qualities!
                    resp_m3u8 = await client.get(master_url, headers={"Referer": base_host + "/"})
                    if resp_m3u8.status_code == 200:
                        parsed_streams = M3U8Parser.parse_master(master_url, resp_m3u8.text)
                        streams.extend(parsed_streams)
                        break # Stop after success"""

good_code = """                    # Simply return the master M3U8 so hls.js can parse all qualities natively
                    streams.append({"url": master_url, "quality": "auto"})
                    break # Stop after success"""

content = content.replace(bad_code, good_code)

with open('AniVerseApiUrl/app/providers/vidsrc.py', 'w') as f:
    f.write(content)
print("Updated vidsrc.py to return master M3U8 directly")
