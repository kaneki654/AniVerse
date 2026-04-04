with open('AniVerse-cli/aniverse.py', 'r') as f:
    content = f.read()

# Remove global import
content = content.replace("import httpx\n", "")

# Add local import to load_data
old_load = """        async with httpx.AsyncClient(timeout=15.0) as client:"""
new_load = """        import httpx
        async with httpx.AsyncClient(timeout=15.0) as client:"""
content = content.replace(old_load, new_load)

# Add local import to play_anime
old_play = """        async with httpx.AsyncClient(timeout=30.0) as client:"""
new_play = """        import httpx
        async with httpx.AsyncClient(timeout=30.0) as client:"""
content = content.replace(old_play, new_play)

with open('AniVerse-cli/aniverse.py', 'w') as f:
    f.write(content)
print("Deferred httpx import!")
