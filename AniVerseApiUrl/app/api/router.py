from fastapi import APIRouter, HTTPException
from app.core.orchestrator import orchestrator
from app.api.proxy import router as proxy_router
from app.services.anilist import anilist_service

router = APIRouter(prefix="/anime", tags=["Anime"])

@router.get("/popular")
async def popular_anime(page: int = 1, per_page: int = 12):
    """Get all-time popular anime"""
    return await anilist_service.get_popular(page, per_page)

@router.get("/trending")
async def trending_anime(page: int = 1, per_page: int = 12):
    """Get currently trending/airing anime"""
    return await anilist_service.get_trending(page, per_page)

@router.get("/search/{query}")
async def search(query: str):
    """
    Search for an anime by name to get its AniList ID.
    """
    result = await anilist_service.search_anime(query)
    if not result:
        raise HTTPException(status_code=404, detail="Anime not found on AniList")
    return result

@router.get("/resolve_by_name/{query}/{episode_number}")
async def resolve_by_name(query: str, episode_number: int, category: str = "sub"):
    """
    Search for an anime by name, automatically grab its AniList ID, and resolve the episode.
    """
    anime_list = await anilist_service.search_anime(query)
    if not anime_list:
        raise HTTPException(status_code=404, detail="Anime not found on AniList")
        
    anime_info = anime_list[0]
    anilist_id = str(anime_info["id"])
    
    try:
        # Pass the dynamically found AniList ID to our Orchestrator
        result = await orchestrator.resolve_episode(anilist_id, episode_number, category)
        
        # Inject the metadata into the response so the frontend knows what it found
        result["metadata"] = {
            "anilist_id": anilist_id,
            "title": anime_info["title"].get("english") or anime_info["title"].get("romaji"),
            "cover": anime_info["coverImage"].get("large")
        }
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/resolve/{anilist_id}/{episode_number}")
async def resolve(anilist_id: str, episode_number: int, category: str = "sub"):
    """
    Direct resolution using AniList ID.
    """
    try:
        result = await orchestrator.resolve_episode(anilist_id, episode_number, category)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


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

# Include proxy router
router.include_router(proxy_router)
