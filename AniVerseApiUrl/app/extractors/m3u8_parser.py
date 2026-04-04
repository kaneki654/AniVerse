import m3u8
from urllib.parse import urljoin
from typing import Dict, Any, List

class M3U8Parser:
    @staticmethod
    def parse_master(playlist_url: str, playlist_content: str) -> List[Dict[str, str]]:
        """
        Parses a master M3U8 playlist and normalizes the relative URLs to absolute.
        """
        playlist = m3u8.loads(playlist_content)
        streams = []
        
        # Check if it's a master playlist with multiple qualities
        if playlist.is_variant:
            for p in playlist.playlists:
                resolution = "unknown"
                if p.stream_info and p.stream_info.resolution:
                    # resolution is a tuple like (1280, 720)
                    resolution = f"{p.stream_info.resolution[1]}p"
                    
                full_url = urljoin(playlist_url, p.uri)
                streams.append({
                    "quality": resolution,
                    "url": full_url
                })
        else:
            # It's a single stream playlist
            streams.append({
                "quality": "auto",
                "url": playlist_url
            })
            
        return streams
