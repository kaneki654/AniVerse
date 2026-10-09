"""Build app/tagalog_sites.json: Tagalog-dubbed anime from the Filipino anime
sites, episode by episode, under AniList ids.

    python scripts/find_tagalog_sites.py            # writes app/tagalog_sites.json
    python scripts/find_tagalog_sites.py --dry-run  # prints what it matched

The sites:
- Senpai Tambayan (a Blogger site): every show is a post whose episode picker
  holds a plain .mp4 link (archive.org, file.garden). Played directly.
- Anime Revival (WordPress, DooPlay): every episode is a page with a Blogger
  video; app/tagalog.py turns that into a Google video link when it is played.

Each site names its shows its own way and splits them into seasons its own way,
so a show is matched on AniList by title (and year, when the site gives one),
then its seasons are laid onto the AniList entry and its sequels. Shows with no
good AniList match -- the Western cartoons, mostly -- are left out; the report
says which. AniList answers are cached in data/anilist_cache.json, so a rerun is
quick.
"""

import argparse
import difflib
import html
import json
import re
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.tagalog import page_videos  # noqa: E402 -- what the server can play
OUT = ROOT / "app" / "tagalog_sites.json"
CACHE = ROOT / "data" / "anilist_cache.json"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130 Safari/537.36"}

SITES = {
    "senpai": {"name": "Senpai Tambayan", "url": "https://www.senpaitambayan.online/"},
    "revival": {"name": "Anime Revival", "url": "https://animerevival.xyz/"},
}

# Where the title alone finds the wrong AniList entry (or none): the site's
# title, normalised (see norm()), -> the AniList id of its first season.
PINNED = {
    "hunter x hunter": 11061,       # the 2011 series
    "hunter x hunter 1999": 136,
    "case closed": 235,
    "detective conan": 235,
    "samurai x": 45,
    "ghost fighter": 392,
    "fruits basket": 105334,        # the remake; the sites have its seasons 1-2
    "code geass": 1575,
    "code geass lelouch of the rebellion": 1575,
    "konosuba": 21202,
    "one punchman": 21087,
    "haikyuu": 20464,
    "eyeshield21": 15,
    "hitman reborn": 1604,
    "frieren beyond journey": 154587,
    "major": 627,                   # AniList calls the seasons "Major S1" ... "Major S6"
    "doraemon old": 2471,           # the 1979 series
    "kancolle kantai collection": 20553,
    "magic kaito kid the phantom thief": 8310,
    "chousoku spinner super yoyo": 2703,
    "yamada kun and the seven witches": 20966,
    "samurai x ova": 44,            # Trust & Betrayal
    "mary at ang lihim na hardin": 2810,
    "hunter x hunter 2011": 11061,
    "horimiya": 124080,             # the series, not the 2012 OVA
    "naruto kid": 20,               # Naruto, before Shippuden
    "detective conan episodes": 235,
    "ippo": 263,                    # Hajime no Ippo, then its sequels
    "cedie": 2555,                  # Little Lord Fauntleroy
    "frieren beyond journeys end": 154587,
    "konosuba gods blessing on this wonderful world": 21202,
    "kurokos basketball": 11771,
    "food wars shokugeki no soma": 20923,
}
# Sites that number a show's episodes the way AniList's single entry does
# ("16x579" is One Piece's episode 579): title -> AniList id.
ABSOLUTE = {"one piece s16 punk hazard": 21}
# Western and Filipino cartoons and live action on the sites, which AniList does
# not list; and pages that hold a part of a show already there under its own name.
NOT_ANIME = {"jackie chan adventures", "the loud house", "spider man", "trese", "dota dragons blood", "skyland",
             "barangay 143", "my family", "avatar the last airbender", "atashinchi", "dexters laboratory",
             "the avengers earths mightiest heroes", "wolverine and the x men", "anime series",
             "one piece fishman island arc",  # lists no episodes
             "mga munting pangarap ni romeo"}  # one marathon video


def norm(title: str) -> str:
    t = unicodedata.normalize("NFKD", html.unescape(title).lower().replace("×", "x"))
    t = "".join(c for c in t if not unicodedata.combining(c)).replace("'", "").replace("\u2019", "")
    t = re.sub(r"\btagalog( dub(bed)?)?\b", " ", t)
    t = re.sub(r"[^a-z0-9 ]+", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def split_season(title: str) -> tuple[str, int]:
    """"Spy x Family S2" -> ("spy x family", 2)."""
    t = norm(title)
    m = re.search(r"\s(?:s|season )(\d+)$", t)
    if m:
        return t[: m.start()].strip(), int(m.group(1))
    return t, 1


# --- AniList -----------------------------------------------------------------------------------

_FIELDS = """id format episodes startDate { year } title { romaji english } synonyms
  relations { edges { relationType node { id type format episodes startDate { year } } } }"""
TV = {"TV", "TV_SHORT", "ONA"}


class AniList:
    def __init__(self):
        self.cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
        self.http = httpx.Client(timeout=30, headers={"Accept": "application/json"})

    def save(self):
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(self.cache))

    def _post(self, query: str, variables: dict):
        key = json.dumps([query, variables], sort_keys=True)
        if key in self.cache:
            return self.cache[key]
        for _attempt in range(6):
            r = self.http.post("https://graphql.anilist.co", json={"query": query, "variables": variables})
            if r.status_code == 429:
                time.sleep(int(r.headers.get("Retry-After", "30")) + 1)
                continue
            r.raise_for_status()
            data = r.json()["data"]
            self.cache[key] = data
            time.sleep(1.0)  # AniList allows 30-90 requests a minute
            return data
        raise RuntimeError("AniList kept rate-limiting")

    def search(self, title: str) -> list[dict]:
        q = f"query ($s: String) {{ Page(perPage: 10) {{ media(search: $s, type: ANIME) {{ {_FIELDS} }} }} }}"
        return self._post(q, {"s": title})["Page"]["media"]

    def get(self, anilist_id: int) -> dict:
        q = f"query ($id: Int) {{ Media(id: $id, type: ANIME) {{ {_FIELDS} }} }}"
        return self._post(q, {"id": anilist_id})["Media"]


def similarity(a: str, m: dict) -> float:
    """1 for the same title; 0.86 when the site shortens it ("Magi" for "Magi:
    The Labyrinth of Magic"); else how alike they read."""
    best = 0.0
    for name in [m["title"].get("english") or "", m["title"].get("romaji") or ""] + (m.get("synonyms") or []):
        n = norm(name)
        if not n:
            continue
        score = difflib.SequenceMatcher(None, a, n).ratio()
        if len(a) >= 4 and n.startswith(a + " "):
            score = max(score, 0.86)
        best = max(best, score)
    return best


def year_of(m: dict) -> int:
    return (m.get("startDate") or {}).get("year") or 9999


def first_season(al: AniList, base: str, year: int | None) -> dict | None:
    if base in ABSOLUTE:
        return al.get(ABSOLUTE[base])
    if base in PINNED:
        return al.get(PINNED[base])
    query = re.sub(r"\s(?:19|20)\d\d$", "", base)
    scored = [(similarity(query, m), m) for m in al.search(query) if m["format"] in TV | {"OVA"}]
    # The same title if there is one, else the close ones; of those the
    # earliest is the first season (or the one from the year the site gives).
    good = [m for s, m in scored if s >= 0.95] or [m for s, m in scored if s >= 0.85]
    if year:
        good = [m for m in good if year_of(m) == year] or good
    return min(good, key=lambda m: (year_of(m), m["id"])) if good else None


def chain(al: AniList, first: dict, length: int) -> list[dict]:
    """The first season and its TV sequels, in order."""
    out = [first]
    while len(out) < length:
        nxt = [e["node"] for e in out[-1]["relations"]["edges"]
               if e["relationType"] == "SEQUEL" and e["node"]["type"] == "ANIME" and e["node"]["format"] in TV]
        if not nxt:
            break
        out.append(al.get(min(nxt, key=lambda n: (year_of(n), n["id"]))["id"]))
    return out


def lay_out(al: AniList, first: dict, seasons: dict[int, dict[int, str]]) -> dict[int, dict[int, str]]:
    """The site's seasons -> {anilist id: {episode: ref}}.

    When each site season fits its AniList entry, season N is the Nth entry.
    Otherwise the site numbers differently (one long season, or seasons that
    split an AniList entry): its episodes are counted straight through and
    poured into the entries in order."""
    order = sorted(seasons)
    entries = chain(al, first, len(order) + 8)
    aligned = len(entries) >= len(order) and all(
        entries[i]["episodes"] is None or max(seasons[s]) <= entries[i]["episodes"] for i, s in enumerate(order))
    out: dict[int, dict[int, str]] = {}
    if aligned:
        for i, s in enumerate(order):
            out.setdefault(entries[i]["id"], {}).update(seasons[s])
        return out
    flat, offset = {}, 0
    for s in order:
        for e, ref in seasons[s].items():
            flat[offset + e] = ref
        offset += max(seasons[s])
    start = 0
    for entry in entries:
        n = entry["episodes"]
        part = {ep - start: ref for ep, ref in flat.items() if ep > start and (n is None or ep <= start + n)}
        if part:
            out[entry["id"]] = part
        if n is None:
            break
        start += n
    return out


# --- the sites ----------------------------------------------------------------------------------

Shows = dict[tuple[str, int | None], dict[int, dict[int, str]]]


def english(url: str) -> bool:
    """An upload marked as the English dub ("...CatENG/01 - A Lonely Cat.MP4"),
    which a few of Senpai Tambayan's posts link to."""
    return bool(re.search(r"ENG(?![a-z])", url) or re.search(r"english", url, re.I))


def senpai(http: httpx.Client) -> Shows:
    """{(title, year): {season: {episode: mp4 url}}}"""
    feed = http.get("https://www.senpaitambayan.online/feeds/posts/summary?alt=json&max-results=500").json()
    shows: Shows = {}
    for entry in feed["feed"].get("entry", []):
        url = next(link["href"] for link in entry["link"] if link["rel"] == "alternate")
        page = http.get(url).text
        episodes = {}
        for attrs, label in re.findall(r"<option([^>]*)>([^<]*)</option>", page):
            mp4 = re.search(r'data-server2="([^"]*)"', attrs)
            mp4 = html.unescape(mp4.group(1)) if mp4 else ""
            m = re.match(r"\s*Episode\s+(\d+)\s*$", html.unescape(label))  # "Episode 1 and 2" is left out
            if m and re.match(r"https://[^\s\"]+\.mp4$", mp4, re.I) and not english(mp4):
                episodes[int(m.group(1))] = mp4
        if episodes:
            base, season = split_season(entry["title"]["$t"])
            shows.setdefault((base, None), {})[season] = episodes
        time.sleep(0.2)
    return shows


def revival(http: httpx.Client) -> Shows:
    """{(title, None): {season: {episode: episode page slug}}}"""
    urls = re.findall(r"<loc>([^<]+)</loc>", http.get("https://animerevival.xyz/tvshows-sitemap.xml").text)
    shows: Shows = {}
    for url in urls:
        if "/tvshows/" not in url:
            continue
        page = http.get(url).text
        h1 = re.search(r"<h1[^>]*>([^<]*)</h1>", page)
        seasons: dict[int, dict[int, str]] = {}
        # The show's own episode list (the sidebar links to other shows' new
        # episodes). Some slugs end in "-2": a second upload, under its own page.
        for m in re.finditer(r'<a class="boxmark-\d+" href="https://animerevival\.xyz/episodes/'
                             r'([a-z0-9%-]+?-(\d+)x(\d+)(?:-\d+)?)/"', page):
            seasons.setdefault(int(m.group(2)), {}).setdefault(int(m.group(3)), m.group(1))
        # A few shows are numbered the other way round: "5x13" for episode 5 of 13.
        if len(seasons) > 1 and all(len(eps) == 1 for eps in seasons.values()) \
                and len({e for eps in seasons.values() for e in eps}) == 1:
            seasons = {1: {s: ref for s, eps in seasons.items() for ref in eps.values()}}
        if h1 and seasons:
            shows[(norm(h1.group(1)), None)] = seasons
        time.sleep(0.2)
    return shows


def revival_playable(slugs: list[str]) -> set[str]:
    """The Anime Revival episodes on a host the server plays (a plain .mp4 or
    Blogger). A show's episodes are spread over hosts -- the later ones often
    on Abyss, whose links are encrypted -- so each episode is checked."""
    def check(slug: str) -> str | None:
        with httpx.Client(headers=UA, timeout=40, follow_redirects=True) as http:
            for _attempt in range(3):
                try:
                    mp4s, tokens = page_videos(http.get(f"https://animerevival.xyz/episodes/{slug}/").text)
                    return slug if mp4s or tokens else None
                except httpx.HTTPError:
                    time.sleep(2)
        return None
    with ThreadPoolExecutor(max_workers=4) as pool:
        return {slug for slug in pool.map(check, slugs) if slug}


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    al = AniList()
    anime: dict[str, dict] = {}
    with httpx.Client(headers=UA, timeout=40, follow_redirects=True) as http:
        for site, crawl in (("senpai", senpai), ("revival", revival)):
            shows = crawl(http)
            keep = None  # every Senpai Tambayan episode is a plain .mp4
            if site == "revival":
                slugs = sorted({ref for seasons in shows.values() for eps in seasons.values() for ref in eps.values()})
                keep = revival_playable(slugs)
                print(f"revival: {len(keep)} of {len(slugs)} episodes on hosts the server plays")
            matched = 0
            for (base, year), seasons in sorted(shows.items()):
                if base in NOT_ANIME or "live action" in base:
                    continue
                given = re.search(r"\s((?:19|20)\d\d)$", base)  # "Hunter x Hunter 1999"
                year = year or (int(given.group(1)) if given else None)
                try:
                    first = first_season(al, base, year)
                except (httpx.HTTPError, RuntimeError) as e:
                    print(f"  {site}: {base!r}: AniList failed ({e})", file=sys.stderr)
                    continue
                if not first:
                    print(f"  {site}: no AniList match for {base!r}", file=sys.stderr)
                    continue
                if base in ABSOLUTE:
                    laid = {first["id"]: {e: ref for eps in seasons.values() for e, ref in eps.items()}}
                else:
                    laid = lay_out(al, first, seasons)
                print(f"  {site}: {base!r} -> " + ", ".join(f"{i} ({len(e)})" for i, e in laid.items()))
                for anilist_id, eps in laid.items():
                    entry = anime.setdefault(str(anilist_id), {"episodes": {}})
                    for ep, ref in eps.items():
                        if keep is None or ref in keep:
                            entry["episodes"].setdefault(str(ep), {})[site] = ref
                matched += 1
                al.save()
            print(f"{site}: {len(shows)} shows, {matched} matched on AniList")
    anime = {i: a for i, a in anime.items() if a["episodes"]}  # shows whose every episode is on Abyss
    for anilist_id, entry in anime.items():
        m = al.get(int(anilist_id))
        entry["title"] = m["title"].get("english") or m["title"].get("romaji") or ""
        entry["episodes"] = dict(sorted(entry["episodes"].items(), key=lambda kv: int(kv[0])))
    al.save()
    total = sum(len(a["episodes"]) for a in anime.values())
    print(f"{len(anime)} AniList entries, {total} episodes")
    if not args.dry_run:
        OUT.write_text(json.dumps({"updated": time.strftime("%Y-%m-%d"), "sites": SITES, "anime": anime},
                                  ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
