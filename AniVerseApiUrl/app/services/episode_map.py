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


async def anizip_episodes(client: httpx.AsyncClient, anilist_id: str) -> Dict[str, dict]:
    """Ani.zip's raw {episode key: episode record} for an AniList entry; {} when
    unavailable. Shared by the provider mapping checks here and the episode
    list on detail pages (services/extras.py), so one fetch serves both."""
    key = f"anizip:episodes:{anilist_id}"
    cached = cache.get(key)
    if cached is not None:
        return cached

    episodes: Dict[str, dict] = {}
    try:
        resp = await client.get(
            ANI_ZIP_URL, params={"anilist_id": str(anilist_id)}, timeout=12
        )
        if resp.status_code == 200:
            episodes = {str(k): v for k, v in ((resp.json() or {}).get("episodes") or {}).items()
                        if isinstance(v, dict)}
    except Exception as e:  # noqa: BLE001 - verification is best-effort
        print(f"Ani.zip episodes failed for {anilist_id}: {e}")

    cache.set(key, episodes, ttl_seconds=CACHE_TTL_SECONDS)
    return episodes


async def episode_titles(client: httpx.AsyncClient, anilist_id: str) -> Dict[str, str]:
    """{episode number: English title} for an AniList entry; {} when unavailable."""
    titles: Dict[str, str] = {}
    for num, episode in (await anizip_episodes(client, anilist_id)).items():
        title = (episode.get("title") or {}).get("en")
        if title:
            titles[num] = title
    return titles


# "Episode 4", or a series name followed by "Episode 4". Anchored at the end so
# a real title that merely mentions a number ("Wound: The Battle for Trost (8)")
# is not caught.
_POSITIONAL_RE = re.compile(r"(?:^|\s)(?:episode|ep)\.?\s*(\d{1,4})\s*$", re.I)


def positional_episode_number(title: str) -> Optional[int]:
    """The N in a title that is only a positional "Episode N" label, else None.

    Sites fill unnamed episodes with a placeholder that restates the number and
    says nothing else. Matching those by text is not just useless, it is unsafe:
    when a show's real first-episode title equals the series name -- "Smoking
    Behind the Supermarket with You" -- it fuzzy-matches that site's "Smoking
    Behind the Supermarket with You Episode 2" at well over any sane threshold,
    so episode 1 silently resolved to episode 2 and episode 2 landed on the same
    file. Callers skip these when correcting numbering by title.
    """
    m = _POSITIONAL_RE.search(title or "")
    return int(m.group(1)) if m else None


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
