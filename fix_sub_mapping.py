with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

old_logic = """                if matches:
                    slug = matches[0]
                    if category == "dub":
                        # Check if -dub exists
                        check_url = f"{self.base_url}/category/{slug}-dub"
                        try:
                            r = await client.get(check_url, follow_redirects=True)
                            if r.status_code == 200 and "Pages not found" not in r.text:
                                return f"{slug}-dub"
                        except Exception:
                            pass
                    return slug"""

new_logic = """                if matches:
                    if category == "sub":
                        # Ensure we don't accidentally pick the dub slug if it was uploaded more recently
                        sub_slug = next((m for m in matches if "-dub" not in m.lower()), matches[0])
                        
                        # Just to be safe, if we picked something like "anime" but "anime-dub" was requested,
                        # the above filter avoids it.
                        return sub_slug
                        
                    elif category == "dub":
                        # We want the dub. See if a dub specifically exists in the search results
                        dub_slug = next((m for m in matches if "-dub" in m.lower()), None)
                        if dub_slug:
                            return dub_slug
                            
                        slug = matches[0]
                        # Check if -dub exists for the main slug
                        check_url = f"{self.base_url}/category/{slug}-dub"
                        try:
                            r = await client.get(check_url, follow_redirects=True)
                            if r.status_code == 200 and "Pages not found" not in r.text:
                                return f"{slug}-dub"
                        except Exception:
                            pass
                        return slug"""

if old_logic in content:
    content = content.replace(old_logic, new_logic)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed sub/dub mapping logic!")
else:
    print("Could not find mapping logic.")
