"""
Official Tagalog dubs (app/tagalog.py): AniList seasons map onto the channels'
straight-through episode numbers, the player page embeds the right video, the
catalogue is sound, and new weekly episodes come in from the RSS feeds --
except members-only ones.
"""

import asyncio
import json
import pathlib
import re
import tempfile
import unittest
from unittest.mock import patch

import httpx
from fastapi.testclient import TestClient

from app import accounts, tagalog
from app.main import app

ROOT = pathlib.Path(__file__).resolve().parent.parent

FAKE = {
    "region": ["PH"],
    "channels": {"muse_ph": {"name": "Muse Philippines", "id": "UCmuse"}},
    "shows": [{
        "key": "dandadan", "title": "DAN DA DAN", "channel": "muse_ph",
        "pattern": r"^DAN DA DAN\s*-\s*Episode\s*(\d+)\s*\[Tagalog\s+Dub\]",
        "seasons": [{"anilist": 171018, "first": 1, "last": 12}, {"anilist": 185660, "first": 13, "last": 24}],
        "episodes": {"1": "vidEp00001", "12": "vidEp00012", "13": "vidEp00013", "14": "vidEp00014"},
    }],
}


class _WithFake(unittest.TestCase):
    def setUp(self):
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        self.dir = pathlib.Path(storage.name)
        cat = self.dir / "tagalog_dubs.json"
        cat.write_text(json.dumps(FAKE))
        for target, name, value in [(tagalog, "CATALOGUE", cat), (accounts, "DATA_DIR", self.dir)]:
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)
        tagalog.reset()
        self.addCleanup(tagalog.reset)


class MappingTest(_WithFake):
    def test_seasons_map_onto_the_channels_numbering(self):
        s1 = tagalog.for_anime(171018)
        s2 = tagalog.for_anime(185660)
        assert s1 is not None and s2 is not None
        self.assertEqual(s1["episodes"], {"1": "vidEp00001", "12": "vidEp00012"})
        # Season 2's first episode is the channel's 13th.
        self.assertEqual(s2["episodes"], {"1": "vidEp00013", "2": "vidEp00014"})
        self.assertEqual(s2["channel"], "Muse Philippines")
        self.assertIsNone(tagalog.for_anime(1))

    def test_routes(self):
        client = TestClient(app)
        self.assertEqual(client.get("/api/tagalog/185660").json()["episodes"]["1"], "vidEp00013")
        self.assertEqual(client.get("/api/tagalog/1").status_code, 404)
        page = client.get("/tagalog/185660/2?start=90")
        self.assertEqual(page.status_code, 200)
        self.assertIn('videoId: "vidEp00014"', page.text)
        self.assertIn("start = 90", page.text)
        self.assertEqual(client.get("/tagalog/185660/9").status_code, 404)  # not dubbed (yet)


class RefreshTest(_WithFake):
    def feed(self, entries):
        items = "".join(f"<entry><yt:videoId>{v}</yt:videoId><title>{t}</title></entry>" for v, t in entries)
        return f"<feed><title>Muse Philippines</title>{items}</feed>"

    def test_new_episodes_come_in_but_members_only_ones_do_not(self):
        feed = self.feed([
            ("vidEp00015", "DAN DA DAN - Episode 15 [Tagalog Dub]｜Muse PH"),
            ("vidEp00016", "DAN DA DAN - Episode 16 [Tagalog Dub]｜Muse PH"),  # members first
            ("vidOther01", "Something else entirely"),
            ("vidEp00013", "DAN DA DAN - Episode 13 [Tagalog Dub]｜Muse PH"),  # already known
        ])

        def handler(request: httpx.Request) -> httpx.Response:
            if "feeds/videos.xml" in str(request.url):
                return httpx.Response(200, text=feed)
            vid = request.url.params.get("v")
            status = "UNPLAYABLE" if vid == "vidEp00016" else "OK"
            return httpx.Response(200, text=f'..."playabilityStatus":{{"status":"{status}"}}...')

        async def run():
            async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
                return await tagalog.refresh_once(client)

        self.assertEqual(asyncio.run(run()), 1)
        s2 = tagalog.for_anime(185660)
        assert s2 is not None
        self.assertEqual(s2["episodes"].get("3"), "vidEp00015")
        self.assertNotIn("4", s2["episodes"])
        # Saved, so a restart keeps it.
        self.assertEqual(json.loads((self.dir / "tagalog_new.json").read_text()), {"dandadan": {"15": "vidEp00015"}})


class CatalogueTest(unittest.TestCase):
    """The real catalogue, as scripts/find_tagalog_dubs.py wrote it."""

    def test_every_entry_is_sound(self):
        cat = json.loads((ROOT / "app" / "tagalog_dubs.json").read_text(encoding="utf-8"))
        self.assertEqual(cat["region"], ["PH"])
        seen_anilist = set()
        for show in cat["shows"]:
            self.assertIn(show["channel"], cat["channels"])
            re.compile(show["pattern"])
            for season in show["seasons"]:
                self.assertNotIn(season["anilist"], seen_anilist)
                seen_anilist.add(season["anilist"])
                self.assertLessEqual(season["first"], season["last"])
            for ep, vid in show["episodes"].items():
                self.assertTrue(ep.isdigit())
                self.assertRegex(vid, r"^[A-Za-z0-9_-]{11}$")
        self.assertGreaterEqual(len(seen_anilist), 10)


if __name__ == "__main__":
    unittest.main()
