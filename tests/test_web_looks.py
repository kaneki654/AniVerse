"""
The website's two looks (app/pixel_web.py): manga by default, pixel art for a
visitor who chose it (the av_look cookie). Every page renders in both, the
install manifest follows the look, and everything the manga pages load exists
-- files, fonts, and an icon for every name the scripts ask for.
"""

import pathlib
import re
import unittest

from fastapi.testclient import TestClient

from app.main import app

ROOT = pathlib.Path(__file__).resolve().parent.parent
STATIC = ROOT / "app" / "static"
PAGES = ["/", "/search", "/genres", "/genre/Action", "/anime/1", "/watch/1/1", "/history", "/account",
         "/schedule", "/mylist", "/settings", "/status", "/offline"]


class LookTest(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_manga_by_default_pixel_by_choice(self):
        manga = self.client.get("/").text
        self.assertIn("/static/manga/manga.css", manga)
        self.assertNotIn("/static/pixel/pixel.css", manga)
        self.client.cookies.set("av_look", "pixel")
        pixel = self.client.get("/").text
        self.assertIn("/static/pixel/pixel.css", pixel)
        self.assertNotIn("/static/manga/", pixel)

    def test_every_page_in_both_looks(self):
        for look in ("manga", "pixel"):
            self.client.cookies.set("av_look", look)
            for page in PAGES:
                with self.subTest(look=look, page=page):
                    r = self.client.get(page)
                    self.assertEqual(r.status_code, 200)
                    self.assertIn(f"/static/{look}/js/", r.text)

    def test_the_manifest_follows_the_look(self):
        m = self.client.get("/manifest.webmanifest").json()
        self.assertEqual(m["name"], "AniVerse")
        self.assertTrue(all(i["src"].startswith("/static/manga/img/") for i in m["icons"]))
        self.client.cookies.set("av_look", "pixel")
        self.assertEqual(self.client.get("/manifest.webmanifest").json()["name"], "AniVerse Pixel")


class MangaAssetsTest(unittest.TestCase):
    def test_everything_the_manga_pages_load_exists(self):
        client = TestClient(app)
        wanted = set()
        for page in PAGES:
            wanted |= set(re.findall(r'/static/manga/[\w./-]+', client.get(page).text))
        css = (STATIC / "manga" / "manga.css").read_text(encoding="utf-8")
        wanted |= {f"/static/manga/{u}" for u in re.findall(r'url\("([\w./-]+)"\)', css)}
        for js in (STATIC / "manga" / "js").glob("*.js"):
            src = js.read_text(encoding="utf-8")
            wanted |= set(re.findall(r'/static/manga/(?:img|sfx)/[\w.-]+\.(?:png|wav)', src))
            wanted |= {f"/static/manga/js/{m}" for m in re.findall(r'from "\./([\w.-]+\.js)"', src)}
        missing = sorted(w for w in wanted if not (ROOT / "app" / w.lstrip("/")).is_file())
        self.assertEqual(missing, [])
        self.assertGreater(len(wanted), 30)

    def test_every_icon_name_has_a_glyph(self):
        icons = set(re.findall(r"^  (\w+): 0x", (STATIC / "manga" / "js" / "icons.js").read_text(), re.M))
        used = set()
        for js in (STATIC / "manga" / "js").glob("*.js"):
            used |= set(re.findall(r'sprite\("(\w+)"', js.read_text(encoding="utf-8")))
        for html in (ROOT / "app" / "templates" / "manga").glob("*.html"):
            used |= set(re.findall(r'data-sprite="(\w+)"', html.read_text(encoding="utf-8")))
        self.assertEqual(sorted(used - icons), [])


if __name__ == "__main__":
    unittest.main()
