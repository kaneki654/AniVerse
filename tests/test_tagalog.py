"""
Tagalog dubs (app/tagalog.py): the catalogue answers per AniList id, an Anime
Revival episode becomes Google video links (best first, the tiny 3GP dropped),
/api/source?category=tl hands them out through the proxy while the .mp4 links
play directly, the 1.12 app's page plays them, and the real catalogue is sound.
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

from app import accounts, proxy_hosts, tagalog
from app.main import app

ROOT = pathlib.Path(__file__).resolve().parent.parent
MP4 = "https://archive.org/download/mha-tagalog/MHA%20S1%20Ep01.mp4"

FAKE = {
    "sites": {"senpai": {"name": "Senpai Tambayan", "url": "https://www.senpaitambayan.online/"},
              "revival": {"name": "Anime Revival", "url": "https://animerevival.xyz/"}},
    "anime": {"21459": {"title": "My Hero Academia", "episodes": {
        "1": {"senpai": MP4, "revival": "my-hero-academia-1x1"},
        "2": {"revival": "my-hero-academia-1x2"},
        "3": {"revival": "my-hero-academia-1x3"},
    }}},
}
EPISODE_PAGE = '<iframe class="metaframe" src="https://www.blogger.com/video.g?token=AD6v5dx-Tok_en1"></iframe>'
RPC = (")]}'\n\n312\n" + json.dumps([["wrb.fr", "WcwnYd", json.dumps([1, None, [
    ["https://rr1---sn-x.googlevideo.com/videoplayback?itag=13&id=a", [13]],
    ["https://rr1---sn-x.googlevideo.com/videoplayback?itag=18&id=a", [18]],
]]), None, None, None, "generic"]]) + "\n25\n[[\"e\",4,null,null,350]]\n")


def blogger(request: httpx.Request) -> httpx.Response:
    if request.url.host == "animerevival.xyz":
        if request.url.path.endswith("-1x2/"):  # some episodes are a plain .mp4, in a video.js player
            return httpx.Response(200, text='<video><source src="https://archive.org/download/mha/Ep2.mp4" type="video/mp4"></video>')
        if request.url.path.endswith("-1x3/"):  # or straight in the player's frame
            return httpx.Response(200, text='<iframe class="metaframe" src="https://animerevival.xyz/files/mha/Ep%2003.mp4"></iframe>')
        return httpx.Response(200, text=EPISODE_PAGE)
    if "batchexecute" in request.url.path:
        assert "AD6v5dx-Tok_en1" in request.content.decode()
        return httpx.Response(200, text=RPC)
    return httpx.Response(404)


class _WithFake(unittest.TestCase):
    def setUp(self):
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        self.dir = pathlib.Path(storage.name)
        cat = self.dir / "tagalog_sites.json"
        cat.write_text(json.dumps(FAKE))
        for target, name, value in [(tagalog, "CATALOGUE", cat), (accounts, "DATA_DIR", self.dir),
                                    (accounts, "DB_PATH", self.dir / "accounts.db")]:
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)
        tagalog.reset()
        self.addCleanup(tagalog.reset)
        proxy_hosts.forget_all()
        self.addCleanup(proxy_hosts.forget_all)


class CatalogueAnswersTest(_WithFake):
    def test_for_anime(self):
        found = tagalog.for_anime(21459)
        assert found is not None
        self.assertEqual(found["episodes"], {"1": "senpai+revival", "2": "revival", "3": "revival"})
        self.assertEqual(found["sites"], ["Anime Revival", "Senpai Tambayan"])
        self.assertIsNone(tagalog.for_anime(1))
        client = TestClient(app)
        self.assertEqual(client.get("/api/tagalog/21459").json()["title"], "My Hero Academia")
        self.assertEqual(client.get("/api/tagalog/1").status_code, 404)


class SourcesTest(_WithFake):
    def run_sources(self, ep):
        async def go():
            async with httpx.AsyncClient(transport=httpx.MockTransport(blogger)) as client:
                return await tagalog.sources(21459, ep, client)
        return asyncio.run(go())

    def test_direct_mp4_first_then_blogger_without_the_3gp(self):
        streams = self.run_sources(1)
        self.assertEqual([(s["server"], s["quality"], s["direct"]) for s in streams],
                         [("Senpai Tambayan", "480p", True), ("Anime Revival", "360p", False)])
        self.assertIn("itag=18", streams[1]["url"])
        self.assertEqual([(s["url"], s["direct"]) for s in self.run_sources(2)],
                         [("https://archive.org/download/mha/Ep2.mp4", True)])
        self.assertEqual([s["url"] for s in self.run_sources(3)], ["https://animerevival.xyz/files/mha/Ep%2003.mp4"])
        self.assertEqual(self.run_sources(9), [])

    def test_api_source_hands_out_the_blogger_link_through_the_proxy(self):
        mock = lambda: httpx.AsyncClient(transport=httpx.MockTransport(blogger))  # noqa: E731
        with patch.object(tagalog, "_new_client", mock):
            client = TestClient(app)
            data = client.get("/api/source", params={"episode_id": "21459/1", "category": "tl"}).json()["data"]
            page = client.get("/tagalog/21459/1?start=95").text
        urls = [s["url"] for s in data["sources"]]
        self.assertEqual(urls[0], MP4)  # played directly
        self.assertTrue(urls[1].startswith("/proxy/stream?url=https%3A%2F%2Frr1---sn-x.googlevideo.com"))
        self.assertTrue(proxy_hosts.allowed("https://rr1---sn-x.googlevideo.com/videoplayback?itag=18"))
        self.assertIsNone(data["error"])
        self.assertIn(json.dumps(MP4), page)
        self.assertIn("start = 95", page)
        self.assertNotIn("youtube", page.lower())

    def test_links_are_asked_for_with_the_proxys_browser(self):
        from app import main
        self.assertEqual(tagalog.UA["User-Agent"], main.USER_AGENT)

    def test_an_episode_nobody_has(self):
        data = TestClient(app).get("/api/source", params={"episode_id": "21459/40", "category": "tl"}).json()["data"]
        self.assertEqual(data["sources"], [])
        self.assertTrue(data["error"])
        self.assertEqual(TestClient(app).get("/tagalog/21459/40").status_code, 404)


class CatalogueTest(unittest.TestCase):
    """The real catalogue, as scripts/find_tagalog_sites.py wrote it."""

    def test_every_entry_is_sound(self):
        cat = json.loads((ROOT / "app" / "tagalog_sites.json").read_text(encoding="utf-8"))
        self.assertEqual(set(cat["sites"]), {"senpai", "revival"})
        for anilist_id, entry in cat["anime"].items():
            self.assertTrue(anilist_id.isdigit())
            self.assertTrue(entry["title"])
            for ep, refs in entry["episodes"].items():
                self.assertTrue(ep.isdigit() and int(ep) > 0, (anilist_id, ep))
                if "senpai" in refs:
                    self.assertRegex(refs["senpai"], r"(?i)^https://\S+\.mp4$")
                if "revival" in refs:
                    self.assertRegex(refs["revival"], r"^[a-z0-9%-]+-\d+x\d+$")
        self.assertGreaterEqual(len(cat["anime"]), 50)
        self.assertGreaterEqual(sum(len(a["episodes"]) for a in cat["anime"].values()), 2000)
        self.assertFalse(re.search("youtube", json.dumps(cat), re.I))


if __name__ == "__main__":
    unittest.main()
