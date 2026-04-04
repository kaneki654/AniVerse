with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

old_resolve = """    async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub") -> Dict[str, Any]:
        cache_key = self._generate_cache_key(anilist_id, episode_number, category)
        cached_data = cache.get(cache_key)
        
        if cached_data:
            return cached_data

        tasks = [
            provider.resolve(anilist_id, episode_number, category)
            for provider in self.providers
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        valid_results = [r for r in results if not isinstance(r, Exception) and "error" not in r]
        
        if not valid_results:
            return {
                "error": "All providers failed (Likely Cloudflare blocking backend IP)", 
                "streams": [{"quality": "auto", "url": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"}]
            }
            
        final_result = self.normalize(valid_results)
        
        # Cache for 1 hour
        cache.set(cache_key, final_result, ttl_seconds=3600)
        
        return final_result"""

new_resolve = """    async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub") -> Dict[str, Any]:
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
        cache.set(cache_key, final_result, ttl_seconds=3600)
        
        return final_result"""

if old_resolve in content:
    content = content.replace(old_resolve, new_resolve)
    with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
        f.write(content)
    print("Fixed orchestrator to cross-pollinate subtitles from sub to dub!")
else:
    print("Could not find orchestrator logic.")
