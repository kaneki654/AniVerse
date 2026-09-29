"""Show how every provider maps an AniList id, to see why an anime will not play.

    python scripts/diagnose_mapping.py 159309 216625 ...

Prints the titles the mappers search with, then each provider's result. The
providers' own log lines (candidates found, why each was rejected) appear
inline, which is usually where the answer is.
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "AniVerseApiUrl"))

import httpx  # noqa: E402

from app.providers.aniwatch import AniWatchProvider  # noqa: E402
from app.providers.aniwatchone import AniWatchOneProvider  # noqa: E402
from app.providers.gogoanime import GogoAnimeProvider  # noqa: E402
from app.providers.vidsrc import VidSrcProvider  # noqa: E402
from app.services import anilist_media  # noqa: E402


async def map_with(provider, client, anilist_id):
    # GogoAnime keys its mapping by audio track; the others do not.
    if isinstance(provider, GogoAnimeProvider):
        return await provider.map_anime(client, anilist_id, "sub")
    return await provider.map_anime(client, anilist_id)


async def diagnose(client, anilist_id):
    info = await anilist_media.get_media(client, anilist_id)
    print(f"\n=== {anilist_id}: ro={info['title_ro']!r} en={info['title_en']!r} "
          f"eps={info['episodes']} format={info['format']}")
    for provider in (GogoAnimeProvider(), AniWatchProvider(), AniWatchOneProvider(), VidSrcProvider()):
        name = provider.__class__.__name__
        try:
            result = await asyncio.wait_for(map_with(provider, client, anilist_id), 90)
        except Exception as e:  # noqa: BLE001 - diagnosis reports, it does not stop
            result = f"EXC {type(e).__name__}: {str(e)[:100]}"
        print(f"  {name:<22} -> {result!r}")


async def main(ids):
    async with httpx.AsyncClient(timeout=40, follow_redirects=True) as client:
        for anilist_id in ids:
            await diagnose(client, anilist_id)


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1:]))
