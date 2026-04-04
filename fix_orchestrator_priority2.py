import re

with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

old_priority = """        def stream_priority(stream):
            url = stream.get("url", "")
            if "vibeplayer.site" in url:
                return 0
            if "cloudnestra.com" in url:
                return 1
            if "premilkyway.com" in url:
                return 10  # Lowest priority
            return 5"""

new_priority = """        def stream_priority(stream):
            url = stream.get("url", "")
            server_name = stream.get("server", "")
            
            # GogoAnime servers (guaranteed correct audio track)
            if "vibeplayer.site" in url:
                return 0
            if "cloudatacdn" in url or "dood" in url.lower() or server_name == "Doodstream":
                return 1
                
            # Fallback providers (might have wrong audio track natively)
            if "cloudnestra.com" in url or server_name == "VidSrc":
                return 5
                
            # Blocked/Unreliable servers
            if "premilkyway.com" in url:
                return 10  
                
            return 8"""

if old_priority in content:
    content = content.replace(old_priority, new_priority)
    with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
        f.write(content)
    print("Fixed orchestrator priority to prefer Doodstream over VidSrc!")
else:
    print("Could not find the priority logic.")
