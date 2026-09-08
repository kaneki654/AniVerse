"""Shared anime metadata layer for the AniVerse frontend and API.

AniList's public GraphQL endpoint currently answers every query with HTTP 403
("The AniList API has been temporarily disabled due to severe stability issues"),
which took down every anime page in the app.

This module keeps AniList as the preferred source -- so pages heal automatically
if it comes back -- but falls back to Kitsu and reshapes Kitsu records into the
AniList response shape.  The fallback re-keys everything onto **AniList IDs**
(via Kitsu's ``mappings`` relationship), so existing URLs, the home-page disk
cache, saved watch history and the stream resolvers (which look anime up by
AniList ID) all keep working untouched.

Every public coroutine returns AniList-shaped media dicts::

    {"id": int, "title": {"romaji": str, "english": str|None},
     "coverImage": {"large": url}, "description": str, "episodes": int|None,
     "genres": [str], "averageScore": int|None, "status": str,
     "duration": int|None, "format": str,
     "nextAiringEpisode": {"episode": int}|None}
"""

import datetime
import math
import os
import time
from typing import Any, Dict, List, Optional, Tuple

import httpx

# Escape hatch: set ANIVERSE_DISABLE_ANILIST=1 to skip AniList entirely and serve
# everything from Kitsu, without waiting for a request to fail first.
DISABLE_ANILIST = os.getenv("ANIVERSE_DISABLE_ANILIST", "").lower() in {"1", "true", "yes"}

ANILIST_URL = "https://graphql.anilist.co"
KITSU_API = "https://kitsu.app/api/edge"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
KITSU_HEADERS = {"Accept": "application/vnd.api+json", "User-Agent": USER_AGENT}

# Kitsu rejects page[limit] above 20 with a 400.
KITSU_PAGE_MAX = 20
DEFAULT_TIMEOUT = 12.0

# AniList -> our normalised status vocabulary.
_KITSU_STATUS = {
    "current": "RELEASING",
    "finished": "FINISHED",
    "tba": "NOT_YET_RELEASED",
    "unreleased": "NOT_YET_RELEASED",
    "upcoming": "NOT_YET_RELEASED",
}

# The handful of genre names where AniList and Kitsu disagree.
_GENRE_ALIASES = {
    "Mahou Shoujo": "Magic",
    "Slice of Life": "Slice of Life",
    "Sci-Fi": "Sci-Fi",
}


# --------------------------------------------------------------------------
# AniList circuit breaker
# --------------------------------------------------------------------------
class _Breaker:
    """Stops us paying a round-trip per request while AniList is hard-down."""

    def __init__(self, cooldown: int = 600):
        self.cooldown = cooldown
        self._open_until = 0.0

    @property
    def is_open(self) -> bool:
        return time.time() < self._open_until

    def trip(self) -> None:
        self._open_until = time.time() + self.cooldown

    def reset(self) -> None:
        self._open_until = 0.0


anilist_breaker = _Breaker()


async def anilist_query(
    query: str,
    variables: Dict[str, Any],
    client: Optional[httpx.AsyncClient] = None,
) -> Optional[Dict[str, Any]]:
    """Run a GraphQL query, or return None if AniList is unavailable."""
    if DISABLE_ANILIST or anilist_breaker.is_open:
        return None

    async def _run(c: httpx.AsyncClient):
        resp = await c.post(
            ANILIST_URL,
            json={"query": query, "variables": variables},
            headers={"User-Agent": USER_AGENT},
            timeout=DEFAULT_TIMEOUT,
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"AniList HTTP {resp.status_code}")
        body = resp.json()
        if body.get("errors") or body.get("data") is None:
            raise RuntimeError(str(body.get("errors"))[:200])
        return body["data"]

    try:
        if client is not None:
            data = await _run(client)
        else:
            async with httpx.AsyncClient() as owned:
                data = await _run(owned)
        anilist_breaker.reset()
        return data
    except Exception as exc:  # noqa: BLE001 - any failure means "use the fallback"
        print(f"[anime_meta] AniList unavailable, falling back to Kitsu: {exc}")
        anilist_breaker.trip()
        return None


# --------------------------------------------------------------------------
# Kitsu plumbing
# --------------------------------------------------------------------------
async def _kitsu_get(
    path: str,
    params: Dict[str, Any],
    client: Optional[httpx.AsyncClient] = None,
) -> Optional[Dict[str, Any]]:
    async def _run(c: httpx.AsyncClient):
        resp = await c.get(
            f"{KITSU_API}{path}",
            params=params,
            headers=KITSU_HEADERS,
            timeout=DEFAULT_TIMEOUT,
        )
        resp.raise_for_status()
        return resp.json()

    try:
        if client is not None:
            return await _run(client)
        async with httpx.AsyncClient() as owned:
            return await _run(owned)
    except Exception as exc:  # noqa: BLE001
        print(f"[anime_meta] Kitsu {path} failed: {exc}")
        return None


def _index_included(payload: Dict[str, Any]) -> Dict[Tuple[str, str], Dict[str, Any]]:
    return {(r["type"], r["id"]): r for r in payload.get("included") or []}


def _related(
    resource: Dict[str, Any],
    name: str,
    included: Dict[Tuple[str, str], Dict[str, Any]],
) -> List[Dict[str, Any]]:
    refs = ((resource.get("relationships") or {}).get(name) or {}).get("data") or []
    if isinstance(refs, dict):  # to-one relationship
        refs = [refs]
    return [included[(r["type"], r["id"])] for r in refs if (r["type"], r["id"]) in included]


def _anilist_id_from_mappings(
    anime: Dict[str, Any],
    included: Dict[Tuple[str, str], Dict[str, Any]],
) -> Optional[int]:
    for mapping in _related(anime, "mappings", included):
        attrs = mapping.get("attributes") or {}
        if attrs.get("externalSite") == "anilist/anime":
            try:
                return int(attrs["externalId"])
            except (KeyError, TypeError, ValueError):
                return None
    return None


def kitsu_to_media(
    anime: Dict[str, Any],
    included: Dict[Tuple[str, str], Dict[str, Any]],
    anilist_id: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """Reshape one Kitsu anime resource into an AniList-shaped media dict."""
    if anilist_id is None:
        anilist_id = _anilist_id_from_mappings(anime, included)
    if anilist_id is None:
        # Without an AniList ID the card would link to a page we cannot resolve.
        return None

    attrs = anime.get("attributes") or {}
    titles = attrs.get("titles") or {}
    romaji = titles.get("en_jp") or attrs.get("canonicalTitle") or titles.get("en")
    english = titles.get("en") or titles.get("en_us")

    poster = attrs.get("posterImage") or {}
    cover = poster.get("large") or poster.get("original") or poster.get("medium")

    score = None
    try:
        if attrs.get("averageRating"):
            score = int(round(float(attrs["averageRating"])))
    except (TypeError, ValueError):
        score = None

    genres = [
        (g.get("attributes") or {}).get("name")
        for g in _related(anime, "genres", included)
    ]
    if not genres:
        genres = [
            (c.get("attributes") or {}).get("title")
            for c in _related(anime, "categories", included)
        ]

    return {
        "id": anilist_id,
        "title": {"romaji": romaji, "english": english},
        "coverImage": {"large": cover},
        "description": attrs.get("synopsis") or attrs.get("description") or "",
        "episodes": attrs.get("episodeCount"),
        "genres": [g for g in genres if g],
        "averageScore": score,
        "status": _KITSU_STATUS.get(attrs.get("status"), "FINISHED"),
        # AniWatch rejects a candidate stream whose runtime is nowhere near the
        # expected one, so episodeLength has to survive the fallback -- without
        # it every show looks like the 24-minute default and the check goes
        # blind. showType maps closely enough onto AniList's format vocabulary.
        "duration": attrs.get("episodeLength"),
        "format": (attrs.get("showType") or "TV").upper(),
        "nextAiringEpisode": None,
    }


def _kitsu_collection(payload: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not payload:
        return []
    included = _index_included(payload)
    out = []
    for anime in payload.get("data") or []:
        media = kitsu_to_media(anime, included)
        if media:
            out.append(media)
    return out


def _paging(page: int, per_page: int) -> Dict[str, Any]:
    limit = max(1, min(per_page, KITSU_PAGE_MAX))
    return {"page[limit]": limit, "page[offset]": max(0, (page - 1) * limit)}


async def _kitsu_anime_list(
    filters: Dict[str, str],
    sort: str,
    page: int,
    per_page: int,
    client: Optional[httpx.AsyncClient] = None,
) -> List[Dict[str, Any]]:
    params = {"sort": sort, "include": "mappings", **_paging(page, per_page)}
    for key, value in filters.items():
        params[f"filter[{key}]"] = value
    return _kitsu_collection(await _kitsu_get("/anime", params, client))


# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------
_MEDIA_FIELDS = """
  id
  title { romaji english }
  description
  coverImage { large }
  episodes
  genres
  averageScore
  status
  duration
  format
  nextAiringEpisode { episode }
"""


async def fetch_media(
    anilist_id: Any,
    client: Optional[httpx.AsyncClient] = None,
) -> Optional[Dict[str, Any]]:
    """Full details for one anime, looked up by its AniList ID."""
    try:
        anilist_id = int(anilist_id)
    except (TypeError, ValueError):
        return None

    data = await anilist_query(
        f"query ($id: Int) {{ Media (id: $id, type: ANIME) {{ {_MEDIA_FIELDS} }} }}",
        {"id": anilist_id},
        client,
    )
    if data and data.get("Media"):
        return data["Media"]

    # Kitsu keeps a reverse index of external IDs, so one request tells us which
    # Kitsu anime belongs to this AniList ID.  Kitsu rejects nested includes, so
    # the genres need a second call against the anime itself.
    payload = await _kitsu_get(
        "/mappings",
        {
            "filter[externalSite]": "anilist/anime",
            "filter[externalId]": str(anilist_id),
            "include": "item",
        },
        client,
    )
    if not payload:
        return None

    kitsu_anime = next(
        (r for r in payload.get("included") or [] if r.get("type") == "anime"), None
    )
    if not kitsu_anime:
        return None

    detailed = await _kitsu_get(
        f"/anime/{kitsu_anime['id']}", {"include": "genres,categories"}, client
    )
    if detailed and detailed.get("data"):
        return kitsu_to_media(
            detailed["data"], _index_included(detailed), anilist_id=anilist_id
        )
    # Genres are a nice-to-have; the mapping response already carries everything else.
    return kitsu_to_media(kitsu_anime, _index_included(payload), anilist_id=anilist_id)


async def fetch_popular(page: int = 1, per_page: int = 12, client=None) -> List[Dict[str, Any]]:
    data = await anilist_query(
        f"""query ($page: Int, $perPage: Int) {{
          Page (page: $page, perPage: $perPage) {{
            media (type: ANIME, sort: POPULARITY_DESC) {{ {_MEDIA_FIELDS} }}
          }}
        }}""",
        {"page": page, "perPage": per_page},
        client,
    )
    if data:
        return ((data.get("Page") or {}).get("media")) or []
    return await _kitsu_anime_list({}, "-userCount", page, per_page, client)


async def fetch_trending(page: int = 1, per_page: int = 12, client=None) -> List[Dict[str, Any]]:
    data = await anilist_query(
        f"""query ($page: Int, $perPage: Int) {{
          Page (page: $page, perPage: $perPage) {{
            media (type: ANIME, sort: TRENDING_DESC) {{ {_MEDIA_FIELDS} }}
          }}
        }}""",
        {"page": page, "perPage": per_page},
        client,
    )
    if data:
        return ((data.get("Page") or {}).get("media")) or []

    payload = await _kitsu_get(
        "/trending/anime", {"limit": min(per_page, KITSU_PAGE_MAX)}, client
    )
    trending = _kitsu_collection(payload)
    if trending:
        return trending
    # /trending is occasionally empty; recently-popular airing shows are a fair stand-in.
    return await _kitsu_anime_list({"status": "current"}, "-userCount", page, per_page, client)


async def fetch_upcoming(page: int = 1, per_page: int = 12, client=None) -> List[Dict[str, Any]]:
    data = await anilist_query(
        f"""query ($page: Int, $perPage: Int) {{
          Page (page: $page, perPage: $perPage) {{
            media (type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) {{ {_MEDIA_FIELDS} }}
          }}
        }}""",
        {"page": page, "perPage": per_page},
        client,
    )
    if data:
        return ((data.get("Page") or {}).get("media")) or []
    return await _kitsu_anime_list({"status": "upcoming"}, "-userCount", page, per_page, client)


async def fetch_latest(page: int = 1, per_page: int = 12, client=None) -> List[Dict[str, Any]]:
    """Recently aired episodes, newest first, with the exact episode number."""
    now = int(time.time())
    data = await anilist_query(
        """query ($page: Int, $perPage: Int, $time: Int) {
          Page (page: $page, perPage: $perPage) {
            airingSchedules (airingAt_lesser: $time, sort: TIME_DESC) {
              episode
              media {
                id
                title { romaji english }
                coverImage { large }
                episodes
                status
              }
            }
          }
        }""",
        {"page": page, "perPage": per_page, "time": now},
        client,
    )
    if data:
        results, seen = [], set()
        for schedule in ((data.get("Page") or {}).get("airingSchedules")) or []:
            media = schedule.get("media")
            if not media or media["id"] in seen:
                continue
            seen.add(media["id"])
            media["exact_latest_episode"] = schedule.get("episode")
            results.append(media)
        return results

    # Kitsu's episode feed is sorted by airdate but also carries future
    # broadcasts and repeats the same show, so walk it a page at a time keeping
    # only episodes that have already aired until we have enough distinct shows.
    today = datetime.date.today().isoformat()
    results: List[Dict[str, Any]] = []
    seen = set()
    offset = max(0, (page - 1) * KITSU_PAGE_MAX)

    for _ in range(4):
        payload = await _kitsu_get(
            "/episodes",
            {
                "sort": "-airdate",
                "include": "media,media.mappings",
                "page[limit]": KITSU_PAGE_MAX,
                "page[offset]": offset,
            },
            client,
        )
        if not payload or not payload.get("data"):
            break

        included = _index_included(payload)
        for episode in payload["data"]:
            attrs = episode.get("attributes") or {}
            airdate = attrs.get("airdate")
            if not airdate or airdate > today:
                continue
            for anime in _related(episode, "media", included):
                media = kitsu_to_media(anime, included)
                if not media or media["id"] in seen:
                    continue
                seen.add(media["id"])
                media["exact_latest_episode"] = attrs.get("number")
                results.append(media)

        if len(results) >= per_page:
            break
        offset += KITSU_PAGE_MAX

    return results[:per_page]


async def search_media(
    query: str = "",
    page: int = 1,
    per_page: int = 20,
    genres: Optional[List[str]] = None,
    client=None,
) -> Dict[str, Any]:
    """Search results plus paging info, in the shape the search page expects."""
    genres = [g for g in (genres or []) if g]

    variables: Dict[str, Any] = {"page": page, "perPage": per_page}
    if query:
        variables["search"] = query
        variables["sort"] = ["SEARCH_MATCH", "POPULARITY_DESC"]
    else:
        variables["sort"] = ["TRENDING_DESC"]
    if genres:
        variables["genres"] = genres

    data = await anilist_query(
        f"""query ($search: String, $genres: [String], $page: Int, $perPage: Int, $sort: [MediaSort]) {{
          Page (page: $page, perPage: $perPage) {{
            pageInfo {{ total currentPage lastPage hasNextPage perPage }}
            media (type: ANIME, search: $search, genre_in: $genres, sort: $sort) {{ {_MEDIA_FIELDS} }}
          }}
        }}""",
        variables,
        client,
    )
    if data:
        page_data = (data.get("Page") or {})
        info = page_data.get("pageInfo") or {}
        return {
            "media": page_data.get("media") or [],
            "currentPage": info.get("currentPage", page),
            "lastPage": info.get("lastPage", 1),
            "hasNextPage": info.get("hasNextPage", False),
        }

    params = {"include": "mappings", **_paging(page, per_page)}
    if query:
        params["filter[text]"] = query
    else:
        params["sort"] = "-userCount"
    if genres:
        params["filter[genres]"] = ",".join(_GENRE_ALIASES.get(g, g) for g in genres)

    payload = await _kitsu_get("/anime", params, client)
    media = _kitsu_collection(payload)
    total = ((payload or {}).get("meta") or {}).get("count") or len(media)
    limit = max(1, min(per_page, KITSU_PAGE_MAX))
    last_page = max(1, math.ceil(total / limit))
    return {
        "media": media,
        "currentPage": page,
        "lastPage": last_page,
        "hasNextPage": page < last_page,
    }


async def fetch_by_genre(genre: str, page: int = 1, per_page: int = 20, client=None):
    result = await search_media("", page, per_page, [genre], client)
    return result["media"]


async def browse_media(
    sort: str = "POPULARITY_DESC", page: int = 1, per_page: int = 20, client=None
) -> List[Dict[str, Any]]:
    data = await anilist_query(
        f"""query ($sort: [MediaSort], $page: Int, $perPage: Int) {{
          Page (page: $page, perPage: $perPage) {{
            media (type: ANIME, sort: $sort) {{ {_MEDIA_FIELDS} }}
          }}
        }}""",
        {"sort": [sort], "page": page, "perPage": per_page},
        client,
    )
    if data:
        return ((data.get("Page") or {}).get("media")) or []

    kitsu_sort = {
        "POPULARITY_DESC": "-userCount",
        "TRENDING_DESC": "-averageRating",
        "SCORE_DESC": "-averageRating",
        "TITLE_ROMAJI": "slug",
        "START_DATE_DESC": "-startDate",
    }.get(sort, "-userCount")
    return await _kitsu_anime_list({}, kitsu_sort, page, per_page, client)


async def fetch_titles(anilist_id: Any, client=None) -> Tuple[str, str]:
    """(romaji, english) for an anime -- used to search streaming providers."""
    media = await fetch_media(anilist_id, client)
    if not media:
        return "", ""
    title = media.get("title") or {}
    return title.get("romaji") or "", title.get("english") or ""
