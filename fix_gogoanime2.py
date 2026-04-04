import re

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()

# Fix the regex to account for newline
old_regex = r"matches = re.findall\(r'<p class=\"name\"><a href=\"/category/\(\[\^\"\]\+\)\"', search_resp.text\)"
new_regex = r"matches = re.findall(r'<p class=\"name\">\s*<a href=\"/category/([^\"]+)\"', search_resp.text)"

if old_regex in content:
    content = content.replace(old_regex, new_regex)
    with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
        f.write(content)
    print("Fixed regex!")
else:
    print("Could not find regex.")

