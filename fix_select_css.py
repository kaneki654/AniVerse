import re

with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Fix CSS height for actions
old_actions = """    .detail-actions {
        height: 3;
        align: left middle;
    }"""

new_actions = """    .detail-actions {
        height: auto;
        align: left middle;
    }"""

if old_actions in content:
    content = content.replace(old_actions, new_actions)
    print("Fixed detail-actions height!")
else:
    print("Could not find detail-actions CSS.")

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)
