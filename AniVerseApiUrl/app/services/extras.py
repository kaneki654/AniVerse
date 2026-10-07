"""
The richer catalogue data behind the 1.9 detail pages, schedule and filters.

- details: trailer, studio, season, relations (sequels/prequels/side stories),
  recommendations and the main characters with their Japanese voice actors.
- episodes: per-episode titles, synopses, air dates and screenshots, from the
  same Ani.zip record episode_map uses to check provider mappings.
- schedule: what airs over the next days, from AniList's airing schedule.
- filter: browsing by year, season, format, status and minimum score.

All of it is extra: every caller copes with an empty answer, so an outage at
AniList or Ani.zip costs these sections and nothing else.
"""

import re
import time
from typing import Any

import httpx

from ..core.cache import cache
from . import anime_meta
from .episode_map import anizip_episodes

_DETAILS_QUERY = """
query ($id: Int) {
  Media (id: $id, type: ANIME) {
    id
    bannerImage
    season
    seasonYear
    trailer { id site thumbnail }
    studios (isMain: true) { nodes { name } }
    relations {
      edges {
        relationType
        node { id type format status episodes title { romaji english } coverImage { large } }
      }
    }
    recommendations (perPage: 12, sort: RATING_DESC) {
      nodes { mediaRecommendation { id format averageScore title { romaji english } coverImage { large } } }
    }
    characters (perPage: 12, sort: [ROLE, RELEVANCE]) {
      edges {
        role
        node { name { full } image { medium } }
        voiceActors (language: JAPANESE) { name { full } image { medium } }
      }
    }
  }
}
"""

# Relations worth a click from an anime page, in the order they are shown.
_RELATION_ORDER = ["PREQUEL", "SEQUEL", "PARENT", "SIDE_STORY", "SPIN_OFF", "ALTERNATIVE", "SUMMARY", "OTHER"]


async def details(anilist_id: int) -> dict[str, Any]:
    key = f"extras:details:{anilist_id}"
    hit = cache.get(key)
    if hit is not None:
        return hit
    data = await anime_meta.anilist_query(_DETAILS_QUERY, {"id": anilist_id})
    media = (data or {}).get("Media") or {}
    if not media:
        return {}

    relations = []
    for edge in (media.get("relations") or {}).get("edges") or []:
        node = edge.get("node") or {}
        kind = edge.get("relationType") or "OTHER"
        # Anime only: the manga it adapts and theme songs are not watchable here.
        if node.get("type") != "ANIME" or node.get("format") == "MUSIC" or kind not in _RELATION_ORDER:
            continue
        relations.append({**_card(node), "relation": kind})
    relations.sort(key=lambda r: _RELATION_ORDER.index(r["relation"]))

    recommendations = [
        _card(n["mediaRecommendation"])
        for n in (media.get("recommendations") or {}).get("nodes") or []
        if n and n.get("mediaRecommendation")
    ]

    characters = []
    for edge in (media.get("characters") or {}).get("edges") or []:
        node = edge.get("node") or {}
        va = (edge.get("voiceActors") or [None])[0] or {}
        characters.append({
            "name": (node.get("name") or {}).get("full"),
            "image": (node.get("image") or {}).get("medium"),
            "role": edge.get("role"),
            "voiceActor": (va.get("name") or {}).get("full"),
            "voiceActorImage": (va.get("image") or {}).get("medium"),
        })

    trailer = media.get("trailer") or {}
    out = {
        "bannerImage": media.get("bannerImage"),
        "season": media.get("season"),
        "seasonYear": media.get("seasonYear"),
        "studio": next((s.get("name") for s in (media.get("studios") or {}).get("nodes") or []), None),
        "trailer": ({"site": trailer["site"], "id": trailer["id"], "thumbnail": trailer.get("thumbnail")}
                    if trailer.get("site") in ("youtube", "dailymotion") and trailer.get("id") else None),
        "relations": relations,
        "recommendations": recommendations,
        "characters": characters,
    }
    cache.set(key, out, ttl_seconds=12 * 3600)
    return out


def _card(node: dict[str, Any]) -> dict[str, Any]:
    """The poster-card shape every client already renders."""
    return {
        "id": node.get("id"),
        "title": node.get("title") or {},
        "coverImage": node.get("coverImage") or {},
        "format": node.get("format"),
        "averageScore": node.get("averageScore"),
        "episodes": node.get("episodes"),
        "status": node.get("status"),
    }


async def episodes(anilist_id: int) -> list[dict[str, Any]]:
    """Numbered episodes with title, synopsis, air date and a screenshot."""
    async with httpx.AsyncClient() as client:
        raw = await anizip_episodes(client, str(anilist_id))
    out = []
    for number, ep in raw.items():
        # Specials are keyed "S1", "S2"...; only numbered episodes are playable.
        if not re.fullmatch(r"\d+", number):
            continue
        titles = ep.get("title") or {}
        out.append({
            "number": int(number),
            "title": titles.get("en") or titles.get("x-jat") or None,
            "overview": ep.get("overview") or ep.get("summary") or None,
            "image": ep.get("image") or None,
            "airDate": ep.get("airDateUtc") or ep.get("airDate") or None,
            "runtime": ep.get("runtime") or ep.get("length") or None,
        })
    out.sort(key=lambda e: e["number"])
    return out


_SCHEDULE_QUERY = """
query ($from: Int, $to: Int, $page: Int) {
  Page (page: $page, perPage: 50) {
    pageInfo { hasNextPage }
    airingSchedules (airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
      airingAt
      episode
      media { id format episodes isAdult averageScore title { romaji english } coverImage { large } }
    }
  }
}
"""


async def schedule(days: int = 7, start: int | None = None) -> list[dict[str, Any]]:
    """Everything airing from `start` (unix seconds, default now) for `days` days."""
    days = max(1, min(days, 14))
    begin = int(start if start is not None else time.time())
    begin -= begin % 1800  # one fetch per half hour, shared by every visitor
    key = f"extras:schedule:{begin}:{days}"
    hit = cache.get(key)
    if hit is not None:
        return hit
    out = []
    for page in range(1, 10):
        data = await anime_meta.anilist_query(_SCHEDULE_QUERY, {"from": begin, "to": begin + days * 86400, "page": page})
        page_data = (data or {}).get("Page") or {}
        for s in page_data.get("airingSchedules") or []:
            media = s.get("media") or {}
            if not media or media.get("isAdult"):
                continue
            out.append({"airingAt": s.get("airingAt"), "episode": s.get("episode"), "media": _card(media)})
        if not (page_data.get("pageInfo") or {}).get("hasNextPage"):
            break
    if out:
        cache.set(key, out, ttl_seconds=1800)
    return out


_FILTER_QUERY = """
query ($page: Int, $perPage: Int, $search: String, $genres: [String], $year: Int, $season: MediaSeason,
       $format: [MediaFormat], $status: MediaStatus, $minScore: Int, $sort: [MediaSort]) {
  Page (page: $page, perPage: $perPage) {
    pageInfo { hasNextPage currentPage lastPage }
    media (type: ANIME, isAdult: false, search: $search, genre_in: $genres, seasonYear: $year, season: $season,
           format_in: $format, status: $status, averageScore_greater: $minScore, sort: $sort) {
      id idMal title { romaji english } coverImage { large } format episodes status averageScore
      nextAiringEpisode { episode } seasonYear season
    }
  }
}
"""

SEASONS = {"WINTER", "SPRING", "SUMMER", "FALL"}
FORMATS = {"TV", "TV_SHORT", "MOVIE", "SPECIAL", "OVA", "ONA"}
STATUSES = {"RELEASING", "FINISHED", "NOT_YET_RELEASED", "HIATUS", "CANCELLED"}
SORTS = {"POPULARITY_DESC", "SCORE_DESC", "TRENDING_DESC", "START_DATE_DESC", "TITLE_ROMAJI", "SEARCH_MATCH"}


async def filter_media(*, q: str = "", genres: list[str] | None = None, year: int | None = None,
                       season: str | None = None, formats: list[str] | None = None, status: str | None = None,
                       min_score: int | None = None, sort: str | None = None, page: int = 1,
                       per_page: int = 24) -> dict[str, Any]:
    """One page of anime matching the filters; `available` is False when AniList
    could not be reached (filters need it: Kitsu cannot filter this way)."""
    variables: dict[str, Any] = {"page": max(1, page), "perPage": max(1, min(per_page, 50))}
    if q:
        variables["search"] = q
    if genres:
        variables["genres"] = genres
    if year:
        variables["year"] = year
    if season in SEASONS:
        variables["season"] = season
    picked = [f for f in (formats or []) if f in FORMATS]
    if picked:
        variables["format"] = picked
    if status in STATUSES:
        variables["status"] = status
    if min_score:
        # AniList filters "greater than"; the UI's "70+" means 70 counts.
        variables["minScore"] = max(0, min(min_score, 100)) - 1
    variables["sort"] = [sort if sort in SORTS else ("SEARCH_MATCH" if q else "POPULARITY_DESC")]
    data = await anime_meta.anilist_query(_FILTER_QUERY, variables)
    page_data = (data or {}).get("Page") or {}
    info = page_data.get("pageInfo") or {}
    return {
        "media": page_data.get("media") or [],
        "hasNextPage": bool(info.get("hasNextPage")),
        "currentPage": info.get("currentPage", page),
        "available": data is not None,
    }
