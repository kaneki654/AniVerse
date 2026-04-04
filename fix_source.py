import re

with open('app/main.py', 'r') as f:
    content = f.read()

bad_source = '''            return {
                "data": {
                    "sources": sources,
                    "subtitles": data.get("subtitles", [])
                }
            }'''

good_source = '''            return {
                "data": {
                    "sources": sources,
                    "subtitles": data.get("subtitles", []),
                    "headers": data.get("headers", {})
                }
            }'''

content = content.replace(bad_source, good_source)

with open('app/main.py', 'w') as f:
    f.write(content)
print("Fixed headers in /api/source")
