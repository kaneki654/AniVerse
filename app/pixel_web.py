"""The website's pixel-art UI, matching the AniVerse Pixel app.

Pages are thin shells: each renders a template from templates/pixel and loads
one script from static/pixel/js, which fetches the same JSON endpoints the app
uses (/api/anime/*, /api/source, /api/auth, /api/history). Nothing here changes
those endpoints, so the app is unaffected by which web UI is on.

main.py installs this ahead of the classic page routes when ANIVERSE_WEB_UI is
"pixel" (the default), so the same URLs serve the new pages; the classic
templates and routes stay as they were and come back with
ANIVERSE_WEB_UI=classic. The manga section is not part of this UI: its URLs
redirect home.
"""

from pathlib import Path

from fastapi import APIRouter, FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

_HERE = Path(__file__).resolve().parent
_STATIC = _HERE / "static" / "pixel"

templates = Jinja2Templates(directory=str(_HERE / "templates"))
# Pages, not API: kept out of the OpenAPI schema, where they would also clash
# with the classic routes of the same name.
router = APIRouter(include_in_schema=False)


def _asset_version() -> str:
    """Changes whenever a pixel asset does, to bust browser caches."""
    newest = max((p.stat().st_mtime for p in _STATIC.rglob("*") if p.is_file()), default=0)
    return str(int(newest))


_VERSION = _asset_version()


def _page(request: Request, name: str, nav: str, title: str, **context) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name=f"pixel/{name}.html",
        context={"page": name, "nav": nav, "title": title, "v": _VERSION, **context},
    )


@router.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return _page(request, "home", "home", "AniVerse")


@router.get("/search", response_class=HTMLResponse)
async def search(request: Request, q: str = ""):
    return _page(request, "search", "search", f"{q} · Search · AniVerse" if q else "Search · AniVerse", q=q)


@router.get("/genres", response_class=HTMLResponse)
async def genres(request: Request):
    return _page(request, "genres", "genres", "Genres · AniVerse")


@router.get("/genre/{name}", response_class=HTMLResponse)
async def genre(request: Request, name: str):
    return _page(request, "genre", "genres", f"{name} · AniVerse", genre=name)


@router.get("/anime/{anime_id:int}", response_class=HTMLResponse)
async def detail(request: Request, anime_id: int):
    return _page(request, "detail", "", "AniVerse", anime_id=anime_id)


@router.get("/watch/{anime_id:int}/{ep:int}", response_class=HTMLResponse)
async def watch(request: Request, anime_id: int, ep: int):
    return _page(request, "watch", "", f"Episode {ep} · AniVerse", anime_id=anime_id, ep=max(1, ep))


@router.get("/history", response_class=HTMLResponse)
async def history(request: Request):
    return _page(request, "history", "history", "History · AniVerse")


@router.get("/account", response_class=HTMLResponse)
async def account(request: Request):
    return _page(request, "account", "account", "Account · AniVerse")


# Pages the pixel UI does not have. The manga section is gone; the A-Z list and
# schedule were thin views of the old hianime API, and search/genres cover them.
@router.get("/manga")
@router.get("/manga/{rest:path}")
async def no_manga():
    return RedirectResponse("/", status_code=302)


@router.get("/azlist/{rest:path}")
@router.get("/anime/browse")
async def no_azlist():
    return RedirectResponse("/genres", status_code=302)


@router.get("/schedule")
async def no_schedule():
    return RedirectResponse("/", status_code=302)


def install(app: FastAPI) -> None:
    """Serve the pixel pages ahead of any classic route on the same path."""
    app.include_router(router)

    @app.middleware("http")
    async def revalidate_pixel_code(request: Request, call_next):
        # Scripts import each other by plain URL, which a version query on the
        # page cannot reach; revalidating (a cheap 304) keeps an update from
        # pairing a new page with an old cached module.
        response = await call_next(request)
        path = request.url.path
        if path.startswith("/static/pixel/") and path.endswith((".js", ".css")):
            response.headers["Cache-Control"] = "no-cache"
        return response
