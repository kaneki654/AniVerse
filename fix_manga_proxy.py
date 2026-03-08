with open('app/main.py', 'r') as f:
    content = f.read()

# Replace the fake proxy with a real redirect
proxy_code = """@app.get("/manga/proxy")
async def basic_manga_proxy(url: str):
    from fastapi.responses import RedirectResponse
    # Quick proxy for JS suggestions
    proxy_url = MANGA_PROXY + url
    return RedirectResponse(proxy_url)"""

import re
content = re.sub(r'@app\.get\("/manga/proxy"\).*?return HTMLResponse[^\n]*', proxy_code, content, flags=re.DOTALL)

with open('app/main.py', 'w') as f:
    f.write(content)
