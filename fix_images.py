import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Replace the image fetch in AnimeCard
old_img = 'resp = httpx.get(img_url, timeout=25.0, headers={"User-Agent": "Mozilla/5.0"}, follow_redirects=True)'
new_img = 'resp = httpx.get(img_url, timeout=15.0, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Referer": "https://anilist.co/"}, follow_redirects=True)'

if old_img in content:
    content = content.replace(old_img, new_img)
    print("Fixed AnimeCard images!")
else:
    print("Could not find AnimeCard image download logic.")

# Replace the image fetch in AnimeDetailScreen
old_detail_img = 'resp = httpx.get(img_url, timeout=10.0, headers={"User-Agent": "Mozilla/5.0"})'
new_detail_img = 'resp = httpx.get(img_url, timeout=15.0, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", "Referer": "https://anilist.co/"}, follow_redirects=True)'

if old_detail_img in content:
    content = content.replace(old_detail_img, new_detail_img)
    print("Fixed AnimeDetailScreen images!")
else:
    # Look for the 25.0 timeout version if the previous fix affected both
    old_detail_img2 = 'resp = httpx.get(img_url, timeout=25.0, headers={"User-Agent": "Mozilla/5.0"}, follow_redirects=True)'
    if old_detail_img2 in content:
        # We probably already replaced all occurrences, but let's check
        pass
    print("Could not find AnimeDetailScreen image download logic (might already be fixed).")

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)
