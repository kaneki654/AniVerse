with open('app/main.py', 'r') as f:
    content = f.read()

bad_url = 'url = f"{NEW_API_BASE}/anime/resolve/{anilist_id}/{ep_num}"'
good_url = 'url = f"{NEW_API_BASE}/anime/resolve/{anilist_id}/{ep_num}?category={category}"'

if bad_url in content:
    content = content.replace(bad_url, good_url)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed get_source to pass category")
else:
    print("Could not find url string in app/main.py")
