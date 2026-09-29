import abc
import unicodedata
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
        title = self.MULTIPART_RE.sub(' ', title.lower())
        title = re.sub(r'[^\w\s]', '', title)
        title = re.sub(r'\b(?:season|part|s)\s*\d+\b', '', title)
        title = re.sub(r'\b\d+(?:st|nd|rd|th)\s+season\b', '', title)
        # "Kensei ni Naru II" is season 2, the same as "... Season 2"; strip it
        # the same way so the two spellings reduce to one base title.
        title = self.ROMAN_SEASON_RE.sub('', title)
        title = re.sub(r'\b(?:ova|ona|special|movie|the\s+movie|film|films?)\b', '', title)
        title = re.sub(r'\s+', ' ', title)
        return title.strip()

    BRACKETED_RE = re.compile(r'[\(\[][^\)\]]*[\)\]]')

    # "Part 1 & 2", "Parts 1-2", "Cour 1 and 2": one entry covering several
    # parts, i.e. the whole season. AniList titles Slime's fourth season
    # "4th Season Part 1 & 2". Read as "Part 1", the "& 2" was left behind in
    # the base title -- "tensei shitara slime datta ken 2" -- and every provider
    # rejected the correct season-4 page it had found, so the #1 trending show
    # could not be played at all.
    MULTIPART_RE = re.compile(
        r'\b(?:parts?|cours?)\s*\d+\s*(?:&|\+|and|to|-|–)\s*\d+\b', re.I)

    def _tidy(self, t: str) -> str:
        """Normalise the separators AniList uses and collapse whitespace."""
        for sign in ("×", "✕", "✖"):
            t = t.replace(sign, " x ")
        return re.sub(r'\s+', ' ', t).strip(" -:")

    def clean_title(self, title: str) -> str:
        """Drop bracketed qualifiers and normalise the separators AniList uses.

        AniList writes "HUNTER×HUNTER (2011)"; catalogue sites index it as
        "Hunter x Hunter", so the raw title matches nothing.

        Some titles are bracketed in full, though -- AniList calls Oshi no Ko's
        second season "[Oshi no Ko] 2nd Season". Dropping the brackets there
        left "2nd Season", which normalize_title() strips down to the empty
        string, so the entry could never match anything and every episode of it
        failed to resolve. When nothing survives, the brackets held the title
        itself, so only the brackets themselves are removed.
        """
        if not title:
            return ""
        title = self.MULTIPART_RE.sub(' ', title)
        stripped = self._tidy(self.BRACKETED_RE.sub(' ', title))
        if not self.normalize_title(stripped):
            stripped = self._tidy(re.sub(r'[\(\[\)\]]', ' ', title))
        return stripped

    def _search_variants(self, title_ro: str, title_en: str) -> List[str]:
        """Ordered, deduped search keywords, most specific first.

        Falls back to progressively shorter forms so a title a site indexes
        without its season/part qualifier is still reachable. Shared because
        every catalogue has this problem: GoGoAnime lists Oshi no Ko's second
        season as "[Oshi No Ko] Season 2", which its search only finds for the
        bare "Oshi no Ko".
        """
        cleaned = [self.clean_title(t) for t in (title_ro, title_en)]

        def flatten(v: str) -> str:
            # "Naruto: Shippuden" -> "Naruto Shippuden" (AniWatch drops the colon).
            return re.sub(r'\s+', ' ', re.sub(r'[:/–—-]', ' ', v)).strip()

        def strip_season(v: str) -> str:
            v = re.sub(r'\s+(?:season|part|cour|s)\s*\d+\s*$', '', v, flags=re.I)
            return re.sub(r'\s+\d+(?:st|nd|rd|th)\s+season\s*$', '', v, flags=re.I)

        def fold(v: str) -> str:
            # "PokéOki" -> "PokeOki": site search indexes the plain letters, and
            # searching with the accent returned nothing at all.
            return "".join(ch for ch in unicodedata.normalize("NFKD", v)
                           if not unicodedata.combining(ch))

        # Tiers, most faithful first: a looser tier is only reached when the
        # tighter ones return nothing, so the lossy prefix-split stays last.
        tiers = [
            cleaned,
            [fold(c) for c in cleaned],
            [flatten(c) for c in cleaned],
            [strip_season(c) for c in cleaned],
            [strip_season(flatten(c)) for c in cleaned],
            [re.split(r'\s*[:–—-]\s+', c)[0] for c in cleaned],
        ]

        variants: List[str] = []
        seen = set()
        for tier in tiers:
            for v in tier:
                v = (v or "").strip(" -:")
                if v and v.lower() not in seen:
                    seen.add(v.lower())
                    variants.append(v)
        return variants

    SEASON_RE = re.compile(
        r'\b(?:season\s*(\d+)|(\d+)(?:st|nd|rd|th)\s+season|s(\d+)\b)', re.I)

    # A closing Roman numeral II-IV is a sequel marker: AniList calls the
    # Bumpkin swordsman's second season "Katainaka no Ossan, Kensei ni Naru II"
    # while the site lists "...Master Swordsman Season 2". Unread, the request
    # became "season 1" and the correct season-2 page was rejected. Unlike a
    # closing digit ("Kaiju No. 8", "Mob Psycho 100") a Roman numeral there is
    # not part of a title, so it is safe to read on both sides of a match.
    ROMAN_SEASON_RE = re.compile(r'\s+(ii|iii|iv)\s*$', re.I)

    def season_of(self, title: str) -> int:
        """Season number a title refers to; 1 when it carries no season marker.

        Lets a mapper tell "Attack on Titan" (season 1) apart from
        "Attack on Titan Season 3", which normalize_title() flattens together.
        """
        m = self.SEASON_RE.search(title or "")
        if not m:
            roman = self.ROMAN_SEASON_RE.search(title or "")
            return self._ROMAN[roman.group(1).lower()] if roman else 1
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
        if self.MULTIPART_RE.search(title or ""):
            return 0
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

    # A bare sequel number closing a title: "...Tough for Mobs 2", "Overlord
    # II". Only 2-9 and II-IV, so "Mob Psycho 100", "Steins;Gate 0" and "86"
    # keep their numbers.
    TRAILING_SEQUEL_RE = re.compile(r'\s+(?:([2-9])|(ii|iii|iv))$')
    _ROMAN = {"ii": 2, "iii": 3, "iv": 4}

    def trailing_sequel(self, norm: str) -> int:
        """Season a normalized title's closing sequel number stands for, else 0."""
        m = self.TRAILING_SEQUEL_RE.search(norm or "")
        if not m:
            return 0
        return int(m.group(1)) if m.group(1) else self._ROMAN[m.group(2)]

    def strip_trailing_sequel(self, norm: str) -> str:
        return self.TRAILING_SEQUEL_RE.sub("", norm or "").strip()

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
            return self._sequel_number_matches(alias, norm_titles, want_season, want_part)
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

    def _sequel_number_matches(self, alias: str, norm_titles: List[str],
                               want_season: int, want_part: int) -> bool:
        """Fallback for a season written as a bare trailing number.

        Sites and AniList both write sequels as "<title> 2" as often as "<title>
        Season 2". Neither says "season", so season_of() read the site's
        "Trapped in a Dating Sim ... for Mobs 2" as season 1, and a season 2
        request rejected the very page it had found. This reads that number as
        the season, only when it is the season asked for, so it can add a
        match the strict rules missed but never take one away -- a blanket rule
        would break titles that simply end in a digit, like "Kaiju No. 8".
        """
        if want_season < 2:
            return False
        # Same part rule as the strict path.
        alias_part = self.part_of(alias)
        if (alias_part != want_part) if want_part else (alias_part > 1):
            return False
        na = self.normalize_title(self.clean_title(alias))
        if self.trailing_sequel(na) != want_season:
            return False
        base = self.strip_trailing_sequel(na)
        return any(self.titles_agree(base, self.strip_trailing_sequel(nt))
                   for nt in norm_titles)

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
