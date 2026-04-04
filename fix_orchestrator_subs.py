with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

bad_normalize = """    def normalize(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        normalized_streams = []
        for res in results:
            if "streams" in res and len(res["streams"]) > 0:
                normalized_streams.extend(res["streams"])
                
        return {
            "streams": normalized_streams,
            "headers": {
                "Referer": "https://cloudnestra.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
        }"""

good_normalize = """    def normalize(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        normalized_streams = []
        normalized_subtitles = []
        for res in results:
            if "streams" in res and len(res["streams"]) > 0:
                normalized_streams.extend(res["streams"])
            if "subtitles" in res:
                normalized_subtitles.extend(res["subtitles"])
                
        return {
            "streams": normalized_streams,
            "subtitles": normalized_subtitles,
            "headers": {
                "Referer": "https://cloudnestra.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
        }"""

if bad_normalize in content:
    content = content.replace(bad_normalize, good_normalize)
    with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
        f.write(content)
    print("Fixed orchestrator.py to pass subtitles")
else:
    print("Could not find normalize string in orchestrator.py")
