import abc
import re
from typing import Dict, Any, List
try:
    from rapidfuzz import fuzz
except ImportError:
    fuzz = None

class BaseProvider(abc.ABC):
    @property
    @abc.abstractmethod
    def name(self) -> str:
        """Provider name"""
        pass

    def normalize_title(self, title: str) -> str:
        """
        Normalize title by removing punctuation, 'season', 'part', etc.
        """
        title = title.lower()
        title = re.sub(r'[^\w\s]', '', title)
        title = re.sub(r'\b(season|part)\s+\d+\b', '', title)
        return title.strip()

    def match_title(self, a: str, b: str) -> bool:
        """
        Fuzzy match two titles.
        """
        if not fuzz:
            # Fallback exact match if rapidfuzz is missing
            return self.normalize_title(a) == self.normalize_title(b)
            
        norm_a = self.normalize_title(a)
        norm_b = self.normalize_title(b)
        return fuzz.ratio(norm_a, norm_b) > 85

    @abc.abstractmethod
    async def resolve(self, anilist_id: str, episode: int, category: str = "sub") -> Dict[str, Any]:
        """
        Full pipeline: Map -> Get Episode -> Get Servers -> Extract
        """
        pass

    @abc.abstractmethod
    async def map_anime(self, anilist_id: str) -> str:
        """Map Anilist ID to Provider Anime ID"""
        pass

    @abc.abstractmethod
    async def get_episode(self, anime_id: str, episode_num: int) -> str:
        """Get Provider Episode ID"""
        pass

    @abc.abstractmethod
    async def get_servers(self, episode_id: str) -> List[Dict[str, str]]:
        """Get Episode Servers"""
        pass

    @abc.abstractmethod
    async def extract(self, servers: List[Dict[str, str]]) -> Dict[str, Any]:
        """Extract streams from servers using ExtractorEngine"""
        pass
