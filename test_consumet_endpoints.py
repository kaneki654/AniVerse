import urllib.request, json

def test_url(url):
    print(f"Testing: {url}")
    try:
        resp = urllib.request.urlopen(url, timeout=10)
        data = json.loads(resp.read())
        
        # Determine format
        if isinstance(data, list):
            print(f"  Result: List ({len(data)} items)")
            if data: print(f"  First item: {data[0]}")
        elif isinstance(data, dict):
            print(f"  Result: Dict (keys: {list(data.keys())})")
            if "results" in data:
                print(f"  Found 'results', looks like a search response. Length: {len(data['results'])}")
            if "chapters" in data:
                print(f"  Found 'chapters', looks like a manga detail response. Length: {len(data['chapters'])}")
    except Exception as e:
        print(f"  Error: {e}")
        
test_url("https://consumet-swart-nine.vercel.app/manga/mangadex/info?id=f0712f04-7528-4b76-bc2e-cd4d7927cb88")
test_url("https://consumet-swart-nine.vercel.app/manga/mangadex/info/f0712f04-7528-4b76-bc2e-cd4d7927cb88")
test_url("https://consumet-swart-nine.vercel.app/manga/mangadex/read?chapterId=6c906663-e4d3-4fc6-bc87-63bb34f6ba6c")
test_url("https://consumet-swart-nine.vercel.app/manga/mangadex/read/6c906663-e4d3-4fc6-bc87-63bb34f6ba6c")
