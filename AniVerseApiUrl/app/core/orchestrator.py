import asyncio
import hashlib
from typing import List, Dict, Any
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
                normalized_streams.extend(res["streams"])
            if "subtitles" in res:
                normalized_subtitles.extend(res["subtitles"])
                
        # Sort streams so that unreliable premilkyway.com streams are pushed to the very bottom,
        # prioritizing vibeplayer and tmstr cloudnestra streams which work 100%.
        def stream_priority(stream):
            url = stream.get("url", "")
            server_name = stream.get("server", "")
            
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

    async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub") -> Dict[str, Any]:
        cache_key = self._generate_cache_key(anilist_id, episode_number, category)
        cached_data = cache.get(cache_key)
        
        if cached_data:
            return cached_data

        tasks = [
            self._resolve_one(provider, anilist_id, episode_number, category)
            for provider in self.providers
        ]
        
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
        other_tasks = [
            self._resolve_one(provider, anilist_id, episode_number, other_category)
            for provider in other_providers
        ]
            
        all_tasks = tasks + other_tasks
        
        all_results = await asyncio.gather(*all_tasks, return_exceptions=True)
        
        results = all_results[:len(tasks)]
        other_results = all_results[len(tasks):]
        
        valid_results = []
        for idx, r in enumerate(results):
            if isinstance(r, Exception):
                print(f"Provider {self.providers[idx].__class__.__name__} failed with exception: {r}")
            elif "error" in r:
                print(f"Provider {self.providers[idx].__class__.__name__} returned error: {r['error']}")
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
        
        # Cache for 1 hour
        cache.set(cache_key, final_result, ttl_seconds=600)
        
        return final_result

from app.providers.vidsrc import VidSrcProvider
from app.providers.gogoanime import GogoAnimeProvider
from app.providers.aniwatch import AniWatchProvider
from app.providers.aniwatchone import AniWatchOneProvider

# Instantiate orchestrator with the REAL VidSrc provider (Cloudflare Immune!)
orchestrator = ResolverOrchestrator(providers=[GogoAnimeProvider(), VidSrcProvider(), AniWatchProvider(), AniWatchOneProvider()])
