import re

# 1. Update BaseProvider
with open('AniVerseApiUrl/app/providers/base.py', 'r') as f:
    content = f.read()
content = content.replace('async def resolve(self, anilist_id: str, episode: int) -> Dict[str, Any]:', 
                          'async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:')
with open('AniVerseApiUrl/app/providers/base.py', 'w') as f:
    f.write(content)

# 2. Update VidSrcProvider
with open('AniVerseApiUrl/app/providers/vidsrc.py', 'r') as f:
    content = f.read()
content = content.replace('async def resolve(self, anilist_id: str, episode: int) -> Dict[str, Any]:', 
                          'async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:')
with open('AniVerseApiUrl/app/providers/vidsrc.py', 'w') as f:
    f.write(content)

# 3. Update GogoAnimeProvider
with open('AniVerseApiUrl/app/providers/gogoanime.py', 'r') as f:
    content = f.read()
content = content.replace('async def resolve(self, anilist_id: str, episode: int) -> Dict[str, Any]:', 
                          'async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:')

# Make GogoAnime aware of dub slugs
map_func_old = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str) -> str:
        """Use Ani.zip API to get the Gogoanime slug from AniList ID"""
        try:
            resp = await client.get(f"https://api.ani.zip/mappings?anilist_id={anilist_id}")
            if resp.status_code == 200:
                data = resp.json()
                if "mappings" in data and "gogoanime" in data["mappings"]:
                    return data["mappings"]["gogoanime"]
        except Exception as e:
            print(f"Mapping error: {e}")
        return ""'''

map_func_new = '''    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str, category: str) -> str:
        """Use Ani.zip API to get the Gogoanime slug from AniList ID"""
        try:
            resp = await client.get(f"https://api.ani.zip/mappings?anilist_id={anilist_id}")
            if resp.status_code == 200:
                data = resp.json()
                if "mappings" in data:
                    mappings = data["mappings"]
                    if category == "dub":
                        if "gogoanime_dub" in mappings:
                            return mappings["gogoanime_dub"]
                        elif "gogoanime" in mappings:
                            return mappings["gogoanime"] + "-dub"
                    else:
                        if "gogoanime" in mappings:
                            return mappings["gogoanime"]
        except Exception as e:
            print(f"Mapping error: {e}")
        return ""'''

content = content.replace(map_func_old, map_func_new)
content = content.replace('anime_slug = await self.map_anime(client, anilist_id)', 'anime_slug = await self.map_anime(client, anilist_id, category)')

with open('AniVerseApiUrl/app/providers/gogoanime.py', 'w') as f:
    f.write(content)

# 4. Update Orchestrator
with open('AniVerseApiUrl/app/core/orchestrator.py', 'r') as f:
    content = f.read()

content = content.replace('def _generate_cache_key(self, anilist_id: str, episode_number: int) -> str:',
                          'def _generate_cache_key(self, anilist_id: str, episode_number: int, category: str) -> str:')
content = content.replace('raw = f"{anilist_id}:{episode_number}"',
                          'raw = f"{anilist_id}:{episode_number}:{category}"')
content = content.replace('async def resolve_episode(self, anilist_id: str, episode_number: int) -> Dict[str, Any]:',
                          'async def resolve_episode(self, anilist_id: str, episode_number: int, category: str = "sub") -> Dict[str, Any]:')
content = content.replace('cache_key = self._generate_cache_key(anilist_id, episode_number)',
                          'cache_key = self._generate_cache_key(anilist_id, episode_number, category)')
content = content.replace('provider.resolve(anilist_id, episode_number)',
                          'provider.resolve(anilist_id, episode_number, category)')

# Add GogoAnimeProvider to the orchestrator!
content = content.replace('from app.providers.vidsrc import VidSrcProvider',
                          'from app.providers.vidsrc import VidSrcProvider\nfrom app.providers.gogoanime import GogoAnimeProvider')
content = content.replace('orchestrator = ResolverOrchestrator(providers=[VidSrcProvider()])',
                          'orchestrator = ResolverOrchestrator(providers=[GogoAnimeProvider(), VidSrcProvider()])')

with open('AniVerseApiUrl/app/core/orchestrator.py', 'w') as f:
    f.write(content)

# 5. Update router
with open('AniVerseApiUrl/app/api/router.py', 'r') as f:
    content = f.read()

content = content.replace('async def resolve_by_name(query: str, episode_number: int):',
                          'async def resolve_by_name(query: str, episode_number: int, category: str = "sub"):')
content = content.replace('result = await orchestrator.resolve_episode(anilist_id, episode_number)',
                          'result = await orchestrator.resolve_episode(anilist_id, episode_number, category)')
content = content.replace('async def resolve(anilist_id: str, episode_number: int):',
                          'async def resolve(anilist_id: str, episode_number: int, category: str = "sub"):')

with open('AniVerseApiUrl/app/api/router.py', 'w') as f:
    f.write(content)

print("Updated providers and orchestrator to support category (sub/dub) and enabled Gogoanime!")
