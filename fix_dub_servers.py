import re

with open('app/main.py', 'r') as f:
    content = f.read()

bad_servers = '"servers": {"sub": [{"serverName": "Auto", "category": "sub"}]},'
good_servers = '''"servers": {
                "sub": [{"serverName": "Auto", "category": "sub"}],
                "dub": [{"serverName": "Auto", "category": "dub"}]
            },'''

content = content.replace(bad_servers, good_servers)

with open('app/main.py', 'w') as f:
    f.write(content)
print("Added dub option to servers format")
