with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_extract = '''                    break # Success!
                    
                except Exception as e:'''

new_extract = '''                    # Instead of breaking on the first server, let's keep checking 
                    # if we haven't found any subtitles yet
                    if not subtitles:
                        continue
                    break # Success!
                    
                except Exception as e:'''

if old_extract in content:
    content = content.replace(old_extract, new_extract)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed Gogoanime extraction to keep searching for subtitles!")
else:
    print("Could not find the extraction logic to fix.")
