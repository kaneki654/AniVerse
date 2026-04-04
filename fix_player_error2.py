import re

with open('app/static/player.js', 'r') as f:
    content = f.read()

# Make sure serverName comparison is robust
old_server_find = "sourceObj = this._cachedSources.find(s => (s.serverName || '') === serverName) || this._cachedSources[0];"
new_server_find = "sourceObj = this._cachedSources.find(s => s.serverName === serverName || serverName === 'Auto') || this._cachedSources[0];"

if old_server_find in content:
    content = content.replace(old_server_find, new_server_find)
    with open('app/static/player.js', 'w') as f:
        f.write(content)
    print("Fixed robust server find in loadSource!")
else:
    print("Could not find the server find logic.")
