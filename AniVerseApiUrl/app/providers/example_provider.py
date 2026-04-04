import httpx
from typing import Dict, Any, List
from .base import BaseProvider
from app.extractors.packed import PackedExtractor
from app.extractors.encrypted import EncryptedExtractor
from app.extractors.html import HTMLScriptIsolator
from app.extractors.m3u8_parser import M3U8Parser
from app.utils.crypto import generate_token

class GenericAnimeProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "GenericAnime"

    async def resolve(self, anilist_id: str, episode: int) -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0) as client:
            anime_id = await self.map_anime(client, anilist_id)
            if not anime_id:
                return {"error": "Anime not found"}
                
            episode_id = await self.get_episode(client, anime_id, episode)
            servers = await self.get_servers(client, episode_id)
            return await self.extract(client, servers)

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str) -> str:
        return f"anime-{anilist_id}"

    async def get_episode(self, client: httpx.AsyncClient, anime_id: str, episode_num: int) -> str:
        return f"{anime_id}-ep-{episode_num}"

    async def get_servers(self, client: httpx.AsyncClient, episode_id: str) -> List[Dict[str, str]]:
        return [{"name": "VidStream", "url": "https://mock-embed.com/1"}]

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        packed_extractor = PackedExtractor()
        streams = []
        
        # WE WILL USE A REAL WORKING M3U8 TEST STREAM SO YOU CAN WATCH A VIDEO
        real_test_stream = "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
        
        for server in servers:
            try:
                # Mocking the HTML to contain a real playable M3U8 file hidden in eval()
                html = f"""
                <html><body><script>
                eval(function(p,a,c,k,e,d){{return 'sources: [{{url: "{real_test_stream}"}}]'}}());
                </script></body></html>
                """
                scripts = HTMLScriptIsolator.extract_scripts(html)
                
                m3u8_url = None
                for script in scripts:
                    if packed_extractor.match(script):
                        res = packed_extractor.extract(script)
                        if res.get("streams"):
                            m3u8_url = res["streams"][0]["url"]
                            break
                            
                if m3u8_url:
                    # In this mock, we just return the master directly
                    # M3U8Parser would normally be used if we downloaded the file
                    streams.append({"quality": "auto", "url": m3u8_url})

            except Exception as e:
                print(f"Extraction failed: {e}")
                
        return {"streams": streams}
