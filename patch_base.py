with open('app/templates/base.html', 'r') as f:
    content = f.read()

nav_item = """<a href="/search" class="nav-item" aria-label="Browse">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>
            </a>"""

# Insert it after the home icon in nav
import re
new_content = re.sub(r'(<a href="/" class="nav-item".*?</a>)', r'\1\n            ' + nav_item, content, count=1, flags=re.DOTALL)

with open('app/templates/base.html', 'w') as f:
    f.write(new_content)
