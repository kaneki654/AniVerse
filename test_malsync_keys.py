import urllib.request
import json
req = urllib.request.urlopen("https://api.malsync.moe/mal/anime/40748")
data = json.loads(req.read())
print(data.get("Sites", {}).keys())
