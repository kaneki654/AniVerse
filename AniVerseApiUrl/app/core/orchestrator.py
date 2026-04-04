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
                
            # Fallback providers (might have wrong audio track natively)
            if "cloudnestra.com" in url or server_name == "VidSrc":
                return 5
                
            # Blocked/Unreliable servers
            if "premilkyway.com" in url:
                return 10  
                
            return 8
            
        normalized_streams.sort(key=stream_priority)
        
        return {
            "streams": normalized_streams,
            "subtitles": normalized_subtitles,
            "headers": {
                "Referer": "https://cloudnestra.com/",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
        }

    async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub") -> Dict[str, Any]:
        cache_key = self._generate_cache_key(anilist_id, episode_number, category)
        cached_data = cache.get(cache_key)
        
        if cached_data:
            return cached_data

        tasks = [
            provider.resolve(anilist_id, episode_number, category)
            for provider in self.providers
        ]
        
        sub_tasks = []
        if category == "dub":
            sub_tasks = [
                provider.resolve(anilist_id, episode_number, "sub")
                for provider in self.providers
            ]
            
        all_tasks = tasks + sub_tasks
        
        all_results = await asyncio.gather(*all_tasks, return_exceptions=True)
        
        results = all_results[:len(tasks)]
        sub_results = all_results[len(tasks):] if category == "dub" else []
        
        valid_results = [r for r in results if not isinstance(r, Exception) and "error" not in r]
        valid_sub_results = [r for r in sub_results if not isinstance(r, Exception) and "error" not in r]
        
        if not valid_results:
            return {
                "error": "All providers failed (Likely Cloudflare blocking backend IP)", 
                "streams": [{"quality": "auto", "url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"}]
            }
            
        final_result = self.normalize(valid_results)
        
        # If dub, borrow subtitles from the sub streams
        if category == "dub" and valid_sub_results:
            borrowed_subtitles = []
            for sub_res in valid_sub_results:
                if "subtitles" in sub_res:
                    borrowed_subtitles.extend(sub_res["subtitles"])
            
            # Remove duplicates based on label/file
            unique_subs = []
            seen_labels = set()
            for sub in borrowed_subtitles:
                if sub["label"] not in seen_labels:
                    seen_labels.add(sub["label"])
                    unique_subs.append(sub)
                    
            if unique_subs:
                final_result["subtitles"] = unique_subs
                
        # Remove duplicate subtitles overall
        if "subtitles" in final_result:
            unique_subs_final = []
            seen_files = set()
            for sub in final_result["subtitles"]:
                if sub["file"] not in seen_files:
                    seen_files.add(sub["file"])
                    unique_subs_final.append(sub)
            final_result["subtitles"] = unique_subs_final
        
        # Cache for 1 hour
        cache.set(cache_key, final_result, ttl_seconds=600)
        
        return final_result

from app.providers.vidsrc import VidSrcProvider
from app.providers.gogoanime import GogoAnimeProvider

# Instantiate orchestrator with the REAL VidSrc provider (Cloudflare Immune!)
orchestrator = ResolverOrchestrator(providers=[GogoAnimeProvider(), VidSrcProvider()])
