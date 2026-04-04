import os

new_endpoints = """
@router.get("/latest")
async def latest_anime(page: int = 1, per_page: int = 12):
    return await anilist_service.get_recently_updated(page, per_page)

@router.get("/upcoming")
async def upcoming_anime(page: int = 1, per_page: int = 12):
    return await anilist_service.get_upcoming(page, per_page)

@router.get("/genre/{genre}")
async def genre_anime(genre: str, page: int = 1, per_page: int = 12):
    return await anilist_service.search_by_genre(genre, page, per_page)

@router.get("/browse")
async def browse_anime(sort: str = "POPULARITY_DESC", page: int = 1, per_page: int = 12):
    return await anilist_service.browse(sort, page, per_page)
"""

file_path = "AniVerseApiUrl/app/api/router.py"
with open(file_path, "r") as f:
    content = f.read()

if "/latest" not in content:
    content = content.replace("# Include proxy router", new_endpoints + "\n# Include proxy router")
    with open(file_path, "w") as f:
        f.write(content)
    print("Added new endpoints to router.py")
else:
    print("Endpoints already exist in router.py")
