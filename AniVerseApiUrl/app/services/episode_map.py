"""Canonical per-episode titles for an AniList entry, from Ani.zip.

Episode counts alone cannot tell the parts of a season apart -- an airing show
has fewer episodes on-site than AniList plans, and a site that merges two cours
into one record legitimately has more. Episode *titles* are unambiguous, so a
mapper can confirm that the entry it picked really is the one AniList asked for
instead of guessing from the title text.
"""

import re
from typing import Dict, Optional

import httpx

from app.core.cache import cache

ANI_ZIP_URL = "https://api.ani.zip/mappings"
CACHE_TTL_SECONDS = 24 * 3600

try:
    from rapidfuzz import fuzz
except ImportError:  # pragma: no cover - rapidfuzz is in requirements
    fuzz = None


async def episode_titles(client: httpx.AsyncClient, anilist_id: str) -> Dict[str, str]:
    """{episode number: English title} for an AniList entry; {} when unavailable."""
    key = f"anizip:eptitles:{anilist_id}"
    cached = cache.get(key)
    if cached is not None:
        return cached

    titles: Dict[str, str] = {}
    try:
        resp = await client.get(
            ANI_ZIP_URL, params={"anilist_id": str(anilist_id)}, timeout=12
        )
        if resp.status_code == 200:
            for num, episode in ((resp.json() or {}).get("episodes") or {}).items():
                title = (episode.get("title") or {}).get("en")
                if title:
                    titles[str(num)] = title
    except Exception as e:  # noqa: BLE001 - verification is best-effort
        print(f"Ani.zip episode titles failed for {anilist_id}: {e}")

    cache.set(key, titles, ttl_seconds=CACHE_TTL_SECONDS)
    return titles


def normalize_episode_title(title: str) -> str:
    return re.sub(r'[^a-z0-9 ]', '', (title or "").lower()).strip()


def titles_match(a: str, b: str, threshold: int = 85) -> bool:
    na, nb = normalize_episode_title(a), normalize_episode_title(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    return bool(fuzz and fuzz.ratio(na, nb) >= threshold)


def match_score(expected: Dict[str, str], found: Dict[str, str], probe: int = 3) -> Optional[float]:
    """Fraction of the first `probe` episodes whose titles agree.

    None when there is nothing to compare, so callers can fall back to their
    other signals rather than treating "unknown" as "wrong".
    """
    if not expected or not found:
        return None
    checked = matched = 0
    for num in sorted(expected, key=lambda n: int(n) if n.isdigit() else 9999)[:probe]:
        if num not in found:
            continue
        checked += 1
        if titles_match(expected[num], found[num]):
            matched += 1
    if not checked:
        return None
    return matched / checked
