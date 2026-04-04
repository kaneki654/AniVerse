import re

with open('app/main.py', 'r') as f:
    content = f.read()

old_route = '@app.get("/proxy/stream")'
new_route = '@app.api_route("/proxy/stream", methods=["GET", "HEAD"])'

if old_route in content:
    content = content.replace(old_route, new_route)
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed proxy_stream to allow HEAD requests!")
else:
    print("Could not find the route annotation.")
