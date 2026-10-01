import asyncio
import hashlib
from typing import Any, Dict, List, Optional, Tuple
from app.providers.base import BaseProvider
from app.core.cache import cache

class ResolverOrchestrator:
    def __init__(self, providers: List[BaseProvider]):
        self.providers = providers

    def _generate_cache_key(self, anilist_id: str, episode_number: int, category: str) -> str:
        raw = f"{anilist_id}:{episode_number}:{category}"
        return hashlib.md5(raw.encode()).hexdigest()

    def normalize(self, results: List[Dict[str, Any]]) -> Dict[str, Any]:
        normalized_streams = []
        normalized_subtitles = []
        for res in results:
            if "streams" in res and len(res["streams"]) > 0:
                # Each stream keeps the subtitle files its own provider gave:
                # they are timed to that encode, and another provider's cut of
                # the same episode can be seconds out (a different intro, a
                # recap). The app shows a source's own tracks, never the pool.
                tracks = [t for t in res.get("subtitles") or []
                          if isinstance(t, dict) and t.get("kind", "captions") in ("captions", "subtitles")]
                for stream in res["streams"]:
                    stream.setdefault("subtitles", tracks)
                normalized_streams.extend(res["streams"])
            if "subtitles" in res:
                normalized_subtitles.extend(res["subtitles"])
                
        # Sort streams so that unreliable premilkyway.com streams are pushed to the very bottom,
        # prioritizing vibeplayer and tmstr cloudnestra streams which work 100%.
        def stream_priority(stream):
            url = stream.get("url", "")
            server_name = stream.get("server", "")
            
            # ZokoAnime is looked up by MyAnimeList ID, not by title, so it
            # cannot land on the wrong show or season, and its audio track is
            # the category it was asked for.
            if server_name == "ZokoAnime":
                return 0

            # GogoAnime servers (guaranteed correct audio track)
            if "vibeplayer.site" in url:
                return 0
            if "cloudatacdn" in url or "dood" in url.lower() or server_name == "Doodstream":
                return 1

            # AniWatchOne Byse HLS streams (sprintcdn / owphbf24 CDN).
            # Ranked above AniWatch: aniwatch.co.at's episode list is correct
            # but the megaplay file it hands back is not the episode it names
            # (AoT S1 eps 1-6 map to MegaPlay files 36088, 36082, 36083, 36080,
            # 36086, 36079 - the right series, shuffled episodes), so those
            # streams play the wrong episode. Byse plays the right one.
            if "sprintcdn" in url or "owphbf24.com" in url:
                return 2

            # AniWatch direct MP4s (my.1anime.site) are reliable direct files
            if "1anime.site" in url:
                return 3

            # AniWatch megaplay HLS streams (cdn/ncdn.watching.onl, *.sugevideo.xyz)
            if "watching.onl" in url or "sugevideo.xyz" in url:
                return 4
                
            # Fallback providers (might have wrong audio track natively)
            if "cloudnestra.com" in url or server_name == "VidSrc":
                return 5
                
            # Blocked/Unreliable servers
            if "premilkyway.com" in url:
                return 10  
                
            return 8
            
        normalized_streams.sort(key=stream_priority)
        
        # Skip markers: take the first provider that actually has them. Only
        # megaplay-backed results carry them, so most results contribute None.
        intro = next((r.get("intro") for r in results if r.get("intro")), None)
        outro = next((r.get("outro") for r in results if r.get("outro")), None)

        return {
            "streams": normalized_streams,
            "subtitles": normalized_subtitles,
            "intro": intro,
            "outro": outro,
            "headers": {
                "Referer": "https://cloudnestra.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
        }

    # A single provider must not be able to hold up the whole response; the
    # others' streams are worth more than one slow provider's.
    PROVIDER_TIMEOUT_SECONDS = 60

    # ...unless nothing else found anything. Byse (AniWatchOne) solves a
    # proof-of-work per stream, one at a time across every request, so when a
    # few episodes resolve at once it queues well past 60s -- and for plenty of
    # mainstream shows it is the only source. A 100-title sweep lost Mob Psycho
    # 100, Konosuba, The Promised Neverland and eight more exactly that way.
    # The extra time is only spent when the episode would otherwise fail, so it
    # costs nothing on any episode that already has a stream.
    LAST_RESORT_EXTRA_SECONDS = 75

    # Once one provider has a stream, the rest get this much longer to add
    # theirs and are then cut off. Waiting the full PROVIDER_TIMEOUT_SECONDS
    # for every straggler held a playable episode back for a minute or more --
    # a 60-title sweep took 60-135s on a third of them while a stream had been
    # ready within seconds -- and to the viewer a spinner that long reads as
    # "not available". The stragglers are fallbacks; the fast ones already are.
    SETTLE_SECONDS = 15

    async def _run(self, provider: BaseProvider, anilist_id: str,
                   episode_number: int, category: str) -> Dict[str, Any]:
        """provider.resolve() with any exception turned into an error result."""
        try:
            return await provider.resolve(anilist_id, episode_number, category)
        except asyncio.CancelledError:
            raise
        except Exception as e:  # noqa: BLE001 - one provider must not sink the rest
            return {"error": f"{provider.__class__.__name__}: {type(e).__name__}: {e}"}

    async def _resolve_requested(self, anilist_id: str, episode_number: int,
                                 category: str) -> Tuple[List[Dict[str, Any]], Optional[float]]:
        """Every provider's result for the requested category, in provider order,
        and the loop time the settle cutoff fell at (None if nothing played).

        Waits for all of them up to PROVIDER_TIMEOUT_SECONDS, as before, except
        that once one has a stream the rest get only SETTLE_SECONDS more. If by
        then nothing has produced a stream and some are still working, those get
        LAST_RESORT_EXTRA_SECONDS more, and the wait ends the moment one of them
        delivers. Anything still running after that is cancelled, which also
        stops a proof-of-work solve mid-way (its cancel flag is set on the way
        out).
        """
        loop = asyncio.get_running_loop()
        tasks = [asyncio.create_task(self._run(p, anilist_id, episode_number, category))
                 for p in self.providers]
        deadline = loop.time() + self.PROVIDER_TIMEOUT_SECONDS
        extended = False
        settle_at = None
        pending = set(tasks)

        def playable() -> bool:
            # In the requested category: a dub request drops sub streams later,
            # so one must not start the settle countdown.
            return any(t.done() and not t.cancelled()
                       and any(s.get("category", category) == category
                               for s in (t.result() or {}).get("streams") or [])
                       for t in tasks)

        while pending:
            if settle_at is None and playable():
                settle_at = min(deadline, loop.time() + self.SETTLE_SECONDS)
                deadline = settle_at
            remaining = deadline - loop.time()
            if remaining <= 0:
                if extended or playable():
                    break
                extended = True
                deadline = loop.time() + self.LAST_RESORT_EXTRA_SECONDS
                slow = ", ".join(p.__class__.__name__ for p, t in zip(self.providers, tasks)
                                 if t in pending)
                print(f"Nothing playable after {self.PROVIDER_TIMEOUT_SECONDS}s for "
                      f"{anilist_id} ep {episode_number} ({category}); giving {slow} "
                      f"{self.LAST_RESORT_EXTRA_SECONDS}s more")
                continue
            _, pending = await asyncio.wait(pending, timeout=remaining,
                                            return_when=asyncio.FIRST_COMPLETED)
            if extended and playable():
                break

        limit = self.PROVIDER_TIMEOUT_SECONDS + (self.LAST_RESORT_EXTRA_SECONDS if extended else 0)
        results = []
        for provider, task in zip(self.providers, tasks):
            name = provider.__class__.__name__
            if task in pending:
                task.cancel()
                if settle_at is not None and not extended:
                    print(f"Provider {name} cut off {self.SETTLE_SECONDS}s after the first stream ({category})")
                else:
                    print(f"Provider {name} timed out after {limit}s ({category})")
                results.append({"error": f"{name} timed out"})
            else:
                results.append(task.result())
        return results, settle_at

    async def _resolve_one(self, provider: BaseProvider, anilist_id: str,
                           episode_number: int, category: str) -> Dict[str, Any]:
        try:
            return await asyncio.wait_for(
                provider.resolve(anilist_id, episode_number, category),
                timeout=self.PROVIDER_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            name = provider.__class__.__name__
            print(f"Provider {name} timed out after {self.PROVIDER_TIMEOUT_SECONDS}s ({category})")
            return {"error": f"{name} timed out"}

    async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub",
                              fresh: bool = False) -> Dict[str, Any]:
        cache_key = self._generate_cache_key(anilist_id, episode_number, category)

        # `fresh` skips the cache. Stream URLs carry tokens that can die long
        # before this ten-minute TTL does -- some are bound to the server's IP,
        # so a router reconnect that changes it kills every cached link at once.
        # Before this, a client whose stream had died got the same dead URL
        # back for the rest of the TTL however many times it asked.
        if not fresh:
            cached_data = cache.get(cache_key)
            if cached_data:
                # Marked so the web layer knows this may be minutes old and
                # checks the links still answer before handing them out.
                return {**cached_data, "cached": True}

        
        # Resolve the opposite category in parallel:
        #  - for "dub": needed to decide if a dub genuinely exists (hasDub)
        #  - for "sub": needed to compute hasDub so the frontend can hide the Audio menu
        #    entry when no provider actually has dubs for this episode.
        # AniWatchOne is excluded: its Byse embeds need a CPU-bound proof-of-work
        # solve, `_pow_gate()` serialises them, and spending one on the opposite
        # category left the requested category without enough time to finish
        # before PROVIDER_TIMEOUT_SECONDS. hasDub is a menu hint; playback is not.
        other_category = "sub" if category == "dub" else "dub"
        other_providers = [p for p in self.providers
                           if p.__class__.__name__ != "AniWatchOneProvider"]
        # Started first so they run alongside the requested category; each is
        # capped at PROVIDER_TIMEOUT_SECONDS and never extended -- hasDub is a
        # menu hint, not worth making anyone wait for.
        other_tasks = [
            asyncio.create_task(self._resolve_one(provider, anilist_id, episode_number, other_category))
            for provider in other_providers
        ]

        results, cut_at = await self._resolve_requested(anilist_id, episode_number, category)
        if cut_at is not None:
            # The requested category was cut short once it had a stream; the
            # probe, started at the same moment, gets no longer than it did.
            # Whatever is still running is "could not determine", not "no".
            loop = asyncio.get_running_loop()
            _, probing = await asyncio.wait(other_tasks, timeout=max(0.0, cut_at - loop.time()))
            for task in probing:
                task.cancel()
        # asyncio.wait never raises for a task's own failure or cancellation,
        # so neither can be mistaken for this request being cancelled.
        await asyncio.wait(other_tasks)
        other_results = [
            {"error": "timed out"} if t.cancelled() else (t.exception() or t.result())
            for t in other_tasks
        ]
        
        valid_results = []
        for idx, r in enumerate(results):
            name = self.providers[idx].__class__.__name__
            if isinstance(r, Exception):
                print(f"Provider {name} failed with exception: {r}")
            elif "error" in r:
                print(f"Provider {name} returned error: {r['error']}")
            elif not r.get("streams"):
                # A provider that mapped and fetched but extracted nothing is a
                # failure, not a result. Counting it as valid used to send back
                # a 200 with an empty stream list and no error, so the player
                # reported "no video resources" with nothing in the log to say
                # why -- and the empty answer was then cached for 10 minutes.
                print(f"Provider {name} returned no streams ({category})")
            else:
                valid_results.append(r)
        
        valid_other_results = [r for r in other_results if not isinstance(r, Exception) and "error" not in r]
        
        # Only trust streams that carry the requested category tag. Providers that
        # silently fall back (e.g. dub -> sub) must not pollute a dub request.
        if category == "dub":
            valid_results = [
                r for r in valid_results
                if any(s.get("category") == "dub" for s in r.get("streams", []))
            ]
        
        # hasDub is tri-state: True / False / None for "could not determine".
        # A provider that timed out proves nothing about whether a dub exists,
        # and reporting False there made the player hide a Dub that does exist.
        other_timed_out = any(
            isinstance(r, Exception) or (isinstance(r, dict) and "timed out" in str(r.get("error", "")))
            for r in other_results
        )
        if category == "dub" and valid_results:
            has_dub = True
        elif any(any(s.get("category") == "dub" for s in r.get("streams", []))
                 for r in valid_other_results):
            has_dub = True
        elif other_timed_out:
            # An unfinished probe is not evidence of absence.
            has_dub = None
        else:
            # Every provider finished the other category and none offered a dub.
            has_dub = False

        if not valid_results:
            return {
                "error": f"No {category} sources available (all providers failed or returned wrong audio)",
                "streams": [],
                "hasDub": has_dub,
            }
            
        final_result = self.normalize(valid_results)
        final_result["hasDub"] = has_dub
        
        # If dub, borrow subtitles from the sub streams
        if category == "dub" and valid_other_results:
            borrowed_subtitles = []
            for sub_res in valid_other_results:
                if "subtitles" in sub_res:
                    borrowed_subtitles.extend(sub_res["subtitles"])
            
            # Remove duplicates based on label/file
            unique_subs = []
            seen_labels = set()
            for sub in borrowed_subtitles:
                sub_label = sub.get("label") or sub.get("lang")
                if sub_label not in seen_labels:
                    seen_labels.add(sub_label)
                    unique_subs.append(sub)
                    
            if unique_subs:
                final_result["subtitles"] = unique_subs
                
        # Remove duplicate subtitles overall
        if "subtitles" in final_result:
            unique_subs_final = []
            seen_files = set()
            for sub in final_result["subtitles"]:
                sub_file = sub.get("file") or sub.get("url")
                if sub_file not in seen_files:
                    seen_files.add(sub_file)
                    unique_subs_final.append(sub)
            final_result["subtitles"] = unique_subs_final
        
        # Only a result that can actually play is worth remembering: caching an
        # empty one turns a momentary upstream failure into ten minutes of an
        # unplayable episode, long after the provider has recovered.
        if final_result.get("streams"):
            cache.set(cache_key, final_result, ttl_seconds=600)
        
        return final_result

from app.providers.vidsrc import VidSrcProvider
from app.providers.gogoanime import GogoAnimeProvider
from app.providers.aniwatch import AniWatchProvider
from app.providers.aniwatchone import AniWatchOneProvider
from app.providers.zokoanime import ZokoAnimeProvider

# Instantiate orchestrator with the REAL VidSrc provider (Cloudflare Immune!)
orchestrator = ResolverOrchestrator(providers=[ZokoAnimeProvider(), GogoAnimeProvider(), VidSrcProvider(), AniWatchProvider(), AniWatchOneProvider()])
