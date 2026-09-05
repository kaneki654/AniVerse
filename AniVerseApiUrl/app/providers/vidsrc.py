import httpx
import re
from typing import Dict, Any, List
from urllib.parse import urlparse

from .base import BaseProvider
from app.extractors.m3u8_parser import M3U8Parser

class VidSrcProvider(BaseProvider):
    @property
    def name(self) -> str:
        return "VidSrc"

    # ani.zip "type" values that correspond to a TMDB *tv* id. A TMDB movie id
    # lives in a different namespace, so feeding it to /embed/tv/ resolves to an
    # unrelated series.
    TV_TYPES = {"TV", "TV_SHORT", "ONA", "OVA", "SPECIAL"}

    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            try:
                mapping = await self._ani_zip(client, anilist_id)
                if not mapping:
                    return {"error": "Anime not found on VidSrc (Mapping failed)"}

                mappings = mapping.get("mappings") or {}
                tmdb_id = mappings.get("themoviedb_id")
                if not tmdb_id:
                    return {"error": "Anime not found on VidSrc (no TMDB id)"}

                media_type = (mappings.get("type") or "").upper()
                if media_type and media_type not in self.TV_TYPES:
                    return {"error": f"VidSrc skipped (TMDB id is not a TV id: {media_type})"}

                episode_id = self._episode_route(mapping, str(tmdb_id), episode)
                if not episode_id:
                    # Guessing season 1 here is what made every season 2+ entry
                    # play season 1, so refuse instead.
                    return {"error": f"VidSrc has no season mapping for episode {episode}"}

                servers = await self.get_servers(client, episode_id)
                if not servers:
                    return {"error": "No embed servers found on VidSrc"}

                return await self.extract(client, servers)
            except Exception as e:
                return {"error": f"VidSrc extraction failed: {str(e)}"}

    async def _ani_zip(self, client: httpx.AsyncClient, anilist_id: str) -> Dict[str, Any]:
        """Full Ani.zip mapping payload (ids plus per-episode season numbers)."""
        try:
            resp = await client.get(f"https://api.ani.zip/mappings?anilist_id={anilist_id}")
            if resp.status_code == 200:
                return resp.json() or {}
        except Exception as e:
            print(f"VidSrc mapping error: {type(e).__name__}: {e}")
        return {}

    async def map_anime(self, client: httpx.AsyncClient, anilist_id: str) -> str:
        """Map AniList ID to TMDB ID using Ani.zip API"""
        mapping = await self._ani_zip(client, anilist_id)
        tmdb_id = (mapping.get("mappings") or {}).get("themoviedb_id")
        return str(tmdb_id) if tmdb_id else ""

    def _episode_route(self, mapping: Dict[str, Any], tmdb_id: str, episode_num: int) -> str:
        """Build the `<tmdb>/<season>/<episode>` route for a VidSrc embed.

        TMDB keys a whole series under one id, so the season must come from the
        mapping. AniList numbers episodes per season while TMDB continues them
        within a season, so use the mapping's episodeNumber too.
        """
        ep = (mapping.get("episodes") or {}).get(str(episode_num))
        if not isinstance(ep, dict):
            return ""
        season = ep.get("seasonNumber")
        number = ep.get("episodeNumber", episode_num)
        if season is None:
            return ""
        return f"{tmdb_id}/{season}/{number}"

    async def get_episode(self, client: httpx.AsyncClient, anilist_id: str, episode_num: int) -> str:
        """Resolve the VidSrc route for an episode via its Ani.zip season mapping.

        Takes the AniList id: Ani.zip is keyed by it, and passing the TMDB id
        here looked up an unrelated show's seasons.
        """
        mapping = await self._ani_zip(client, anilist_id)
        tmdb_id = (mapping.get("mappings") or {}).get("themoviedb_id")
        if not tmdb_id:
            return ""
        return self._episode_route(mapping, str(tmdb_id), episode_num)

    async def get_servers(self, client: httpx.AsyncClient, episode_id: str) -> List[Dict[str, str]]:
        """Scrape VidSrc for the iframe source"""
        url = f"https://vidsrc.me/embed/tv/{episode_id}"
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
        
        try:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return []
                
            match = re.search(r'iframe[^>]+src="([^"]+)"', resp.text)
            if match:
                iframe_src = match.group(1)
                if iframe_src.startswith("//"):
                    iframe_src = "https:" + iframe_src
                return [{"name": "VidSrc", "url": iframe_src}]
            return []
        except Exception:
            return []

    async def extract(self, client: httpx.AsyncClient, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        """
        Extract the prorcp iframe and parse the PlayerJS configuration for the M3U8.
        """
        streams = []
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        
        for server in servers:
            try:
                iframe_url = server["url"]
                parsed_url = urlparse(iframe_url)
                base_host = f"{parsed_url.scheme}://{parsed_url.netloc}"
                
                resp = await client.get(iframe_url, headers={"Referer": "https://vidsrc.me/"})
                if resp.status_code != 200:
                    continue
                    
                match = re.search(r"src:\s*'(/prorcp/[^']+)'", resp.text)
                if not match:
                    continue
                    
                prorcp_url = base_host + match.group(1)
                resp2 = await client.get(prorcp_url, headers={"Referer": base_host + "/"})
                
                # Extract the M3U8 string from the PlayerJS setup
                m3u8_match = re.search(r'file:\s*"([^"]+)"', resp2.text)
                subtitles = []
                if m3u8_match:
                    raw_m3u8 = m3u8_match.group(1)
                    urls = raw_m3u8.split(" or ")
                    if urls:
                        master_url = urls[0].replace("{v1}", parsed_url.netloc)
                        streams.append({"url": master_url, "quality": "auto",
                                        "server": server.get("name", "VidSrc"),
                                        "category": "sub"})
                    
                    subs_match = re.search(r'subtitle:\s*"([^"]+)"', resp2.text)
                    if subs_match:
                        raw_subs = subs_match.group(1)
                        for s in raw_subs.split(","):
                            m = re.search(r'\[(.*?)\](.*)', s)
                            if m:
                                subtitles.append({"file": m.group(2), "label": m.group(1), "kind": "captions"})
                    
                    # Also fallback: if no subs found in setup, we can fetch OpenSubtitles or Aniskip etc here, but for now we rely on the provider.
                    # Keep looking through servers if we haven't found subtitles
                    if not subtitles:
                        continue
                        
                    # Return right away with both streams and subtitles
                    return {"streams": streams, "subtitles": subtitles}
                        
            except Exception as e:
                print(f"VidSrc Extraction Failed: {e}")
                continue
                
        return {"streams": streams}
