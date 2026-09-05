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
        Normalize title by removing punctuation, 'season', 'part', movies, etc.
        """
        title = title.lower()
        title = re.sub(r'[^\w\s]', '', title)
        title = re.sub(r'\b(?:season|part|s)\s*\d+\b', '', title)
        title = re.sub(r'\b\d+(?:st|nd|rd|th)\s+season\b', '', title)
        title = re.sub(r'\b(?:ova|ona|special|movie|the\s+movie|film|films?)\b', '', title)
        title = re.sub(r'\s+', ' ', title)
        return title.strip()

    def clean_title(self, title: str) -> str:
        """Drop bracketed qualifiers and normalise the separators AniList uses.

        AniList writes "HUNTER×HUNTER (2011)"; catalogue sites index it as
        "Hunter x Hunter", so the raw title matches nothing.
        """
        if not title:
            return ""
        t = re.sub(r'[\(\[][^\)\]]*[\)\]]', ' ', title)
        for sign in ("×", "✕", "✖"):
            t = t.replace(sign, " x ")
        return re.sub(r'\s+', ' ', t).strip(" -:")

    SEASON_RE = re.compile(
        r'\b(?:season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+season|s(\d+)\b)', re.I)

    def season_of(self, title: str) -> int:
        """Season number a title refers to; 1 when it carries no season marker.

        Lets a mapper tell "Attack on Titan" (season 1) apart from
        "Attack on Titan Season 3", which normalize_title() flattens together.
        """
        m = self.SEASON_RE.search(title or "")
        if not m:
            return 1
        for g in m.groups():
            if g:
                try:
                    return int(g)
                except ValueError:
                    return 1
        return 1

    PART_RE = re.compile(
        r'\b(?:part|cour)\s*(\d+)|\b(\d+)(?:st|nd|rd|th)\s+(?:part|cour)\b', re.I)

    def part_of(self, title: str) -> int:
        """Part/cour number a title refers to; 0 when it carries no part marker.

        normalize_title() strips "Part N", so "Final Season Part 1" and
        "Final Season Part 2" flatten to the same string and season_of() reads 1
        for both. Without this, a multi-part show matches every one of its parts
        and the winner is decided by search order, which is how "Final Season"
        ended up playing Part 2.
        """
        m = self.PART_RE.search(title or "")
        if not m:
            return 0
        for g in m.groups():
            if g:
                try:
                    return int(g)
                except ValueError:
                    return 0
        return 0

    def titles_agree(self, candidate: str, target: str) -> bool:
        """Whether two normalized titles denote the same entry.

        An exact match wins. Otherwise only near-identical spellings pass:
        equal fuzz alone would accept "dragon ball z" for "dragon ball", so a
        candidate carrying extra words is rejected as a different entry in the
        same franchise.
        """
        if not candidate or not target:
            return False
        if candidate == target:
            return True
        if set(candidate.split()) == set(target.split()):
            return True
        if fuzz and fuzz.ratio(candidate, target) >= 95:
            return True
        return False

    def series_matches(self, alias: str, norm_titles: List[str],
                       want_season: int, want_part: int) -> bool:
        """Whether `alias` names the same entry as any of `norm_titles`.

        Season and part are compared before the titles are normalized, because
        normalize_title() strips both -- that is what let a season 3 request
        accept a "Final Season Part 2" page.
        """
        if not alias:
            return False
        if self.season_of(alias) != want_season:
            return False
        alias_part = self.part_of(alias)
        if want_part:
            if alias_part != want_part:
                return False
        elif alias_part > 1:
            # AniList names no part, so this is the season's first entry. Sites
            # label that either "<title>" or "<title> Part 1" -- both are fine,
            # but an explicit "Part 2" is a different release and normalize_title
            # would otherwise flatten it onto the same name.
            return False
        na = self.normalize_title(self.clean_title(alias))
        return any(self.titles_agree(na, nt) for nt in norm_titles)

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
