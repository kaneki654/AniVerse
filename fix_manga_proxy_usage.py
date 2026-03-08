import re

with open('app/main.py', 'r') as f:
    content = f.read()

# Fix proxy usages
# We don't need proxy_base in contexts anymore, but it's harmless.
# The critical one is in manga_read
old_manga_read = """                        page["img"] = MANGA_PROXY + quote(page["img"], safe='')"""
new_manga_read = """                        # Consumet pages usually don't need proxy if we use no-referrer
                        # Just ensure domain is correct if it's mangadex
                        page["img"] = page["img"].replace("https://mangadex.org", "https://uploads.mangadex.org")"""

content = content.replace(old_manga_read, new_manga_read)

# Fix basic proxy
old_basic_proxy = """@app.get("/manga/proxy")
async def basic_manga_proxy(url: str):
    from fastapi.responses import RedirectResponse
    # Quick proxy for JS suggestions
    proxy_url = MANGA_PROXY + url
    return RedirectResponse(proxy_url)"""
new_basic_proxy = """@app.get("/manga/proxy")
async def basic_manga_proxy(url: str):
    from fastapi.responses import RedirectResponse
    # Since proxy is broken, just redirect to the fixed URL
    fixed_url = url.replace("https://mangadex.org", "https://uploads.mangadex.org")
    return RedirectResponse(fixed_url)"""

content = content.replace(old_basic_proxy, new_basic_proxy)

with open('app/main.py', 'w') as f:
    f.write(content)
