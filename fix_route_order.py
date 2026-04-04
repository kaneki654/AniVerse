import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Extract the browse route
browse_pattern = re.compile(r'@app\.get\("/anime/browse", response_class=HTMLResponse\).*?return templates\.TemplateResponse\(request=request, name="browse\.html", context=\{"data": data\}\)', re.DOTALL)
match = browse_pattern.search(content)

if match:
    browse_code = match.group(0)
    
    # Remove it from its current location
    content = content.replace(browse_code, '')
    
    # Insert it right before @app.get("/anime/{anime_id}")
    detail_pattern = r'@app\.get\("/anime/\{anime_id\}", response_class=HTMLResponse\)'
    content = re.sub(detail_pattern, browse_code + '\n\n' + detail_pattern, content)
    
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("Fixed route order")
else:
    print("Could not find browse route")
