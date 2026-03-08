import urllib.request, json

def test_url(url):
    print(f"Testing: {url}")
    try:
        resp = urllib.request.urlopen(url, timeout=10)
        data = json.loads(resp.read())
        return data
    except Exception as e:
        print(f"  Error: {e}")
        return None

info = test_url("https://consumet-swart-nine.vercel.app/manga/mangadex/info/f0712f04-7528-4b76-bc2e-cd4d7927cb88")
if info and "chapters" in info and len(info["chapters"]) > 0:
    chapter_id = info["chapters"][0]["id"]
    print(f"Got valid chapter ID: {chapter_id}")
    
    # Test read with query param
    res1 = test_url(f"https://consumet-swart-nine.vercel.app/manga/mangadex/read?chapterId={chapter_id}")
    if isinstance(res1, list):
        print("Success with query param!")
        print(res1[0])
    
    # Test read with path param
    res2 = test_url(f"https://consumet-swart-nine.vercel.app/manga/mangadex/read/{chapter_id}")
    if isinstance(res2, list):
        print("Success with path param!")
        print(res2[0])
