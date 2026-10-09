"""Build app/tagalog_dubs.json: official Tagalog dubs, episode by episode.

The Tagalog dubs come from the Philippine licensees' own YouTube channels
(Muse Philippines, Ani-One Philippines, Ani-One PH Collection), free and legal to watch there and
embeddable -- but only in the Philippines, and some (Ani-One's ULTRA) only for
paying channel members, which are left out. AniVerse plays them in YouTube's
own embedded player, so the views and the ads stay with the channel.

Run by hand to (re)build the catalogue:

    python scripts/find_tagalog_dubs.py            # writes app/tagalog_dubs.json
    python scripts/find_tagalog_dubs.py --dry-run  # just prints what it found
    python scripts/find_tagalog_dubs.py --only sentenced_hero,my_hero_academia
                                                   # redo these shows, keep the rest

It reads the channels' public pages and official RSS feeds. Each episode is
checked to be watchable (not members-only, not removed) before it is listed.
Between runs the server picks up new weekly episodes of these shows by itself,
from the channels' RSS feeds (app/tagalog.py), using the same title patterns.
"""

import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app" / "tagalog_dubs.json"

CHANNELS = {
    "muse_ph": {"name": "Muse Philippines", "id": "UC6sKhWSlPSWIh6e4ukisDHQ"},
    "anione_ph": {"name": "Ani-One Philippines", "id": "UCZGEjiTMwMv-Mf-t3VLBlJQ"},
    # Whole seasons as one "full marathon" video each.
    "anione_ph_collection": {"name": "Ani-One PH Collection", "id": "UCKwe-CrlORY6sF8kLsFB5qw"},
}

# Each show: where it is, how its episode titles read (group 1 = the channel's
# episode number; no group = a single video), and which AniList entry covers
# which of the channel's episode numbers -- the channels number straight
# through the seasons, AniList splits them. A show that is only up as marathon
# videos lists them under "marathons" instead; its episodes are cut from their
# chapters ("Episode #14" at 00:23:50, ...).
SHOWS = [
    {
        "key": "spy_family", "title": "SPY x FAMILY", "search": "Spy x Family", "channel": "muse_ph",
        "pattern": r"^Spy x Family\s*-?\s*Episode\s*(\d+)\s*\[TAGALOG\s+Dub\]",
        "playlists": ["PLY0CZDH3Um6A"],  # a short, older-style playlist id; it is real
        "queries": ["Spy x Family Tagalog Dub", "Spy x Family Episode Tagalog Dub Muse PH"],
        "seasons": [{"anilist": 140960, "first": 1, "last": 12}, {"anilist": 142838, "first": 13, "last": 25},
                    {"anilist": 158927, "first": 26, "last": 37}, {"anilist": 177937, "first": 38, "last": 50}],
    },
    {
        "key": "spy_family_code_white", "title": "SPY x FAMILY CODE: White", "channel": "muse_ph",
        "pattern": r"SPY x FAMILY CODE: White \[TAGALOG Dub\]",
        "queries": ["SPY x FAMILY CODE: White TAGALOG Dub"],
        "seasons": [{"anilist": 158928, "first": 1, "last": 1}],
    },
    {
        "key": "dandadan", "title": "DAN DA DAN", "channel": "muse_ph",
        "pattern": r"^DAN DA DAN\s*-\s*Episode\s*(\d+)\s*\[Tagalog\s+Dub\]",
        "playlists": ["PLFyTtoGG2UkqIgPu_uFWS7wqO3y2mn6-L"],
        "queries": ["DAN DA DAN Tagalog Dub", "DAN DA DAN Episode Tagalog Dub Muse PH"],
        "seasons": [{"anilist": 171018, "first": 1, "last": 12}, {"anilist": 185660, "first": 13, "last": 24}],
    },
    {
        "key": "frieren", "title": "Frieren: Beyond Journey's End", "channel": "muse_ph",
        "pattern": r"^Frieren: Beyond Journey's End\s*-\s*Episode\s*(\d+)\s*\[TAGALOG\s+Dub\]",
        "playlists": ["PLFyTtoGG2UkrzuPE_Zbs2-rLoDD1CiqV6"],
        "queries": ["Frieren Tagalog Dub", "Frieren Beyond Journey's End Episode Tagalog Dub"],
        "seasons": [{"anilist": 154587, "first": 1, "last": 28}],
    },
    {
        "key": "kaiju_no_8", "title": "Kaiju No. 8", "channel": "anione_ph",
        "pattern": r"^Kaiju No\. 8 (?:\| Episode|Season 2 Ep) #(\d+) \(TAG Dub\)",
        "queries": ["Kaiju No. 8 TAG Dub", "Kaiju No. 8 Season 2 TAG Dub", "Kaiju No. 8 Episode TAG Dub"],
        "seasons": [{"anilist": 153288, "first": 1, "last": 12}, {"anilist": 178754, "first": 13, "last": 23}],
    },
    {
        "key": "gachiakuta", "title": "Gachiakuta", "channel": "anione_ph",
        "pattern": r"^Gachiakuta \| Episode #(\d+) \(TAG Dub\)",
        "playlists": ["PLJ6dlV7_7bdUOjaty29yMSaHFCBp_97f5"],
        "queries": ["Gachiakuta TAG Dub", "Gachiakuta Episode TAG Dub"],
        "seasons": [{"anilist": 178025, "first": 1, "last": 24}],
    },
    {
        "key": "sentenced_hero", "title": "Sentenced to Be a Hero", "channel": "anione_ph",
        "pattern": r"^《Sentenced to Be a Hero》 #(\d+) \(TAG Dub\)",
        "queries": ["Sentenced to Be a Hero TAG Dub", "《Sentenced to Be a Hero》 TAG Dub Ani-One Philippines"],
        "seasons": [{"anilist": 167152, "first": 1, "last": 12}],
    },
    {
        "key": "my_hero_academia", "title": "My Hero Academia", "channel": "anione_ph_collection",
        "marathons": ["c7qks5U3dX0", "qTMlq6PF1pI"],  # Season 1 (Ep 1-13), Season 2 (Ep 14-38)
        "seasons": [{"anilist": 21459, "first": 1, "last": 13}, {"anilist": 21856, "first": 14, "last": 38}],
    },
]

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64)", "Accept-Language": "en"}


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")


def initial_data(page: str) -> dict:
    m = re.search(r"var ytInitialData = (\{.*?\});</script>", page)
    return json.loads(m.group(1)) if m else {}


def videos_in(data) -> list[tuple[str, str]]:
    """(videoId, title) for every video on a YouTube page."""
    out = []

    def walk(o):
        if isinstance(o, dict):
            r = o.get("videoRenderer")
            if r and r.get("videoId"):
                title = "".join(x.get("text", "") for x in r.get("title", {}).get("runs", []))
                out.append((r["videoId"], title))
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
    walk(data)
    return out


def playlist_feed(playlist_id: str) -> list[tuple[str, str]]:
    """The official RSS feed of a playlist (its first 15 videos)."""
    x = fetch(f"https://www.youtube.com/feeds/videos.xml?playlist_id={playlist_id}")
    ids = re.findall(r"<yt:videoId>([^<]+)</yt:videoId>", x)
    titles = re.findall(r"<title>([^<]+)</title>", x)[1:]
    return [(v, html.unescape(t)) for v, t in zip(ids, titles)]


def channel_search(channel_id: str, query: str) -> list[tuple[str, str]]:
    page = fetch(f"https://www.youtube.com/channel/{channel_id}/search?query={urllib.parse.quote(query)}")
    return [(v, html.unescape(t)) for v, t in videos_in(initial_data(page))]


def watchable(video_id: str) -> tuple[bool, str]:
    """Free to watch (not members-only, not removed), as YouTube itself says."""
    page = fetch(f"https://www.youtube.com/watch?v={video_id}")
    m = re.search(r'"playabilityStatus":\{"status":"([A-Z_]+)"(?:,"reason":"([^"]*)")?', page)
    status, reason = (m.group(1), m.group(2) or "") if m else ("UNKNOWN", "")
    return status == "OK", reason


def chapters(video_id: str) -> dict[int, list[int]]:
    """A marathon video's episodes: {episode: [start, end]} in seconds, from its chapters."""
    page = fetch(f"https://www.youtube.com/watch?v={video_id}")
    marks = [(int(n), int(ms) // 1000) for n, ms in re.findall(
        r'"chapterRenderer":\{"title":\{"simpleText":"Episode #?(\d+)[^"]*"\},"timeRangeStartMillis":(\d+)', page)]
    if not marks:  # no chapter bar: the description's "00:23:50 - Episode #15" lines
        m = re.search(r'"shortDescription":"((?:[^"\\]|\\.)*)"', page)
        desc = json.loads(f'"{m.group(1)}"') if m else ""
        for t, n in re.findall(r"^\s*((?:\d+:)?\d+:\d\d)\s*-\s*Episode\s*#?(\d+)", desc, re.M):
            secs = 0
            for part in t.split(":"):
                secs = secs * 60 + int(part)
            marks.append((int(n), secs))
    length = re.search(r'"lengthSeconds":"(\d+)"', page)
    ends = [start for _, start in marks[1:]] + [int(length.group(1)) if length else 0]
    return {n: [start, end] for (n, start), end in zip(marks, ends) if end > start}


def episode_of(show: dict, title: str) -> int | None:
    m = re.search(show["pattern"], title, re.I)
    if not m:
        return None
    return int(m.group(1)) if m.groups() else 1


def build_marathons(show: dict, pause: float) -> tuple[dict[str, str], dict[str, list[int]]]:
    episodes, clips = {}, {}
    for video in show["marathons"]:
        ok, reason = watchable(video)
        time.sleep(pause)
        if not ok:
            print(f"    skip {show['key']} marathon {video}: {reason or 'not watchable'}", file=sys.stderr)
            continue
        for ep, clip in chapters(video).items():
            episodes[str(ep)], clips[str(ep)] = video, clip
        time.sleep(pause)
    return episodes, clips


def build(show: dict, pause: float) -> dict[str, str]:
    channel = CHANNELS[show["channel"]]["id"]
    found: dict[int, str] = {}
    seen: set[str] = set()

    def take(pairs):
        for vid, title in pairs:
            ep = episode_of(show, title)
            if ep and vid not in seen and ep not in found:
                seen.add(vid)
                found[ep] = vid

    for pl in show.get("playlists", []):
        take(playlist_feed(pl))
        time.sleep(pause)
    for q in show["queries"]:
        take(channel_search(channel, q))
        time.sleep(pause)
    # Anything still missing: ask for that episode by number. YouTube's search
    # is not repeatable -- the same query finds a video one time and not the
    # next -- so a missing episode gets a few rounds and two phrasings.
    last = max(s["last"] for s in show["seasons"])
    name = show.get("search", show["title"])  # as the channel writes it
    for _round in range(3):
        for ep in range(1, last + 1):
            if ep in found or last == 1:
                continue
            for q in (f"{name} Episode {ep:02d} Tagalog Dub", f"{name} Episode {ep:02d} Tagalog"):
                take(channel_search(channel, q))
                time.sleep(pause)
                if ep in found:
                    break

    episodes = {}
    for ep in sorted(found):
        ok, reason = watchable(found[ep])
        time.sleep(pause)
        if ok:
            episodes[str(ep)] = found[ep]
        else:
            print(f"    skip {show['key']} #{ep} ({found[ep]}): {reason or 'not watchable'}", file=sys.stderr)
    return episodes


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--pause", type=float, default=0.6, help="seconds between requests")
    ap.add_argument("--only", help="comma-separated show keys to redo; the others are kept as they are")
    args = ap.parse_args()
    only = set(args.only.split(",")) if args.only else None
    unknown = (only or set()) - {s["key"] for s in SHOWS}
    if unknown:
        ap.error(f"no such show: {', '.join(sorted(unknown))}")
    kept = {}
    if only and OUT.exists():
        kept = {s["key"]: s for s in json.loads(OUT.read_text(encoding="utf-8"))["shows"]}
    shows = []
    for show in SHOWS:
        if only and show["key"] not in only and show["key"] in kept:
            shows.append(kept[show["key"]])
            continue
        clips = {}
        if show.get("marathons"):
            episodes, clips = build_marathons(show, args.pause)
        else:
            episodes = build(show, args.pause)
        first = min(s["first"] for s in show["seasons"])
        last = max(s["last"] for s in show["seasons"])
        missing = [e for e in range(first, last + 1) if str(e) not in episodes]
        print(f"{show['key']:<24} {len(episodes):>3} episodes" + (f"  (missing {missing})" if missing else ""))
        entry = {k: show[k] for k in ("key", "title", "channel", "pattern", "seasons") if k in show}
        shows.append(entry | {"episodes": episodes} | ({"clips": clips} if clips else {}))
    catalogue = {
        "updated": time.strftime("%Y-%m-%d"),
        "about": "Official Tagalog dubs on the licensees' YouTube channels; built by scripts/find_tagalog_dubs.py.",
        "region": ["PH"],
        "channels": CHANNELS,
        "shows": shows,
    }
    if not args.dry_run:
        OUT.write_text(json.dumps(catalogue, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
