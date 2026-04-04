with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

old_norm = """    def normalize(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        normalized_streams = []
        normalized_subtitles = []
        for res in results:
            if "streams" in res and len(res["streams"]) > 0:
                normalized_streams.extend(res["streams"])
            if "subtitles" in res:
                normalized_subtitles.extend(res["subtitles"])
                
        return {"""

new_norm = """    def normalize(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        normalized_streams = []
        normalized_subtitles = []
        for res in results:
            if "streams" in res and len(res["streams"]) > 0:
                normalized_streams.extend(res["streams"])
            if "subtitles" in res:
                normalized_subtitles.extend(res["subtitles"])
                
        # Sort streams so that unreliable premilkyway.com streams are pushed to the very bottom,
        # prioritizing vibeplayer and tmstr cloudnestra streams which work 100%.
        def stream_priority(stream):
            url = stream.get("url", "")
            if "vibeplayer.site" in url:
                return 0
            if "cloudnestra.com" in url:
                return 1
            if "premilkyway.com" in url:
                return 10  # Lowest priority
            return 5
            
        normalized_streams.sort(key=stream_priority)
        
        return {"""

if old_norm in content:
    content = content.replace(old_norm, new_norm)
    with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
        f.write(content)
    print("Fixed orchestrator to prioritize reliable streams!")
else:
    print("Could not find normalize logic.")
