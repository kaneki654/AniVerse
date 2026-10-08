"""The 1.9 server features: My List sync, stream reports, sealed tracking
tokens, tracking progress, watch parties and housekeeping. Everything runs
against temporary databases and folders.

Run with: python3 -m pytest -q tests/test_v19_features.py
"""

import asyncio
import importlib.util
import json
from typing import Any
import os
import pathlib
import sqlite3
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app import accounts, party, reports, secretbox, tracking
from app.main import app

ROOT = pathlib.Path(__file__).resolve().parent.parent


class _Isolated(unittest.TestCase):
    """A fresh accounts database and data folder for every test."""

    def setUp(self):
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        self.dir = pathlib.Path(storage.name)
        for target, name, value in [
            (accounts, "DB_PATH", self.dir / "accounts.db"),
            (accounts, "DATA_DIR", self.dir),
            (accounts, "_initialised", False),
            (accounts, "_failed_logins", {}),
            (accounts, "_registrations", {}),
            (reports, "_salt", None),
            (secretbox, "_fernet", None),
        ]:
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)
        env = patch.dict(os.environ, {"ANIVERSE_SECRET_KEY": ""})
        env.start()
        self.addCleanup(env.stop)
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def sign_up(self, name="WatchFan"):
        r = self.client.post("/api/auth/register", json={"username": name, "password": "test-password-42"})
        self.assertEqual(r.status_code, 200, r.text)
        return {"Authorization": f"Bearer {r.json()['token']}"}, r.json()["user"]["id"]


class WatchlistTest(_Isolated):
    def test_newest_change_wins_and_removals_sync(self):
        headers, _ = self.sign_up()
        put = lambda entries: self.client.put("/api/watchlist", headers=headers, json={"entries": entries})
        r = put([{"anime_id": "154587", "title": "Frieren", "cover": "", "seen_episode": 12, "updated_at": 1000}])
        self.assertEqual(r.status_code, 200, r.text)
        # An older write from another device does not undo the newer one.
        put([{"anime_id": "154587", "title": "Frieren", "cover": "", "seen_episode": 3, "updated_at": 500}])
        entries = self.client.get("/api/watchlist", headers=headers).json()["entries"]
        self.assertEqual([(e["anime_id"], e["seen_episode"]) for e in entries], [("154587", 12)])
        # A removal is kept as a tombstone so it reaches other devices.
        put([{"anime_id": "154587", "title": "Frieren", "cover": "", "seen_episode": 12, "updated_at": 2000, "deleted": True}])
        entries = self.client.get("/api/watchlist", headers=headers).json()["entries"]
        self.assertTrue(entries[0]["deleted"])

    def test_needs_an_account(self):
        self.assertEqual(self.client.get("/api/watchlist").status_code, 401)


class ReportsTest(_Isolated):
    URL = "/proxy/m3u8?url=https%3A%2F%2Fcdn.example%2Fep3.m3u8"

    def report(self, ip, reason="Keeps buffering"):
        return self.client.post("/api/report", headers={"cf-connecting-ip": ip},
                                json={"episode_id": "154587/3", "category": "sub", "url": self.URL, "reason": reason})

    def test_one_report_hides_it_only_for_the_reporter(self):
        self.assertEqual(self.report("10.0.0.1").status_code, 200)
        self.assertEqual(reports.hidden("154587", "3", "sub", "10.0.0.1"), {"https://cdn.example/ep3.m3u8"})
        self.assertEqual(reports.hidden("154587", "3", "sub", "10.0.0.2"), set())

    def test_two_people_hide_it_for_everyone(self):
        self.report("10.0.0.1")
        self.report("10.0.0.2")
        self.assertEqual(reports.hidden("154587", "3", "sub", "10.9.9.9"), {"https://cdn.example/ep3.m3u8"})
        # Other episodes and the other audio are untouched.
        self.assertEqual(reports.hidden("154587", "4", "sub"), set())
        self.assertEqual(reports.hidden("154587", "3", "dub"), set())

    def test_rate_limited_per_person(self):
        for i in range(reports.PER_HOUR):
            r = self.client.post("/api/report", headers={"cf-connecting-ip": "10.0.0.7"},
                                 json={"episode_id": f"1/{i}", "category": "sub", "url": self.URL})
            self.assertEqual(r.status_code, 200)
        self.assertEqual(self.report("10.0.0.7").status_code, 429)

    def test_reports_outlive_a_restart_and_store_no_addresses(self):
        self.report("10.0.0.1")
        self.report("10.0.0.2")
        reports._salt = None  # as if the server had restarted
        self.assertTrue(reports.hidden("154587", "3", "sub"))
        rows = sqlite3.connect(accounts.DB_PATH).execute("SELECT reporter FROM stream_reports").fetchall()
        self.assertTrue(all("10.0.0" not in r[0] for r in rows))

    def test_rejects_junk(self):
        bad = self.client.post("/api/report", json={"episode_id": "nope", "url": self.URL})
        self.assertEqual(bad.status_code, 400)
        bad = self.client.post("/api/report", json={"episode_id": "1/1", "url": "javascript:alert(1)"})
        self.assertEqual(bad.status_code, 400)


class SecretboxTest(_Isolated):
    def test_round_trip_and_legacy_plaintext(self):
        sealed = secretbox.seal("tok_" + "x" * 40) or ""
        self.assertTrue(sealed.startswith("enc:"))
        self.assertNotIn("xxxx", sealed)
        self.assertEqual(secretbox.unseal(sealed), "tok_" + "x" * 40)
        self.assertEqual(secretbox.seal(sealed), sealed)  # never sealed twice
        self.assertEqual(secretbox.unseal("plain-old-token"), "plain-old-token")
        self.assertIsNone(secretbox.seal(None))
        self.assertTrue((self.dir / "secret.key").exists())
        self.assertEqual(oct((self.dir / "secret.key").stat().st_mode & 0o777), "0o600")

    def test_another_key_cannot_open_it(self):
        sealed = secretbox.seal("tok_secret_value_123456")
        secretbox._fernet = None
        (self.dir / "secret.key").write_text("")  # a different key next time
        with patch.dict(os.environ, {"ANIVERSE_SECRET_KEY": "Zm9vYmFyZm9vYmFyZm9vYmFyZm9vYmFyZm9vYmFyMTI="}):
            self.assertIsNone(secretbox.unseal(sealed))


class TrackingTest(_Isolated):
    def test_anilist_token_is_checked_and_stored_sealed(self):
        headers, user_id = self.sign_up()
        token = "tok_" + "x" * 40
        with patch.object(tracking, "_anilist", AsyncMock(return_value={"Viewer": {"id": 77, "name": "Kai"}})):
            r = self.client.post("/api/tracking/anilist", headers=headers, json={"token": token})
        self.assertEqual(r.json(), {"connected": True, "account": "Kai"})
        stored = sqlite3.connect(accounts.DB_PATH).execute(
            "SELECT token, refresh FROM tracking WHERE user_id = ?", (user_id,)).fetchone()
        self.assertTrue(stored[0].startswith("enc:"))
        self.assertEqual(stored[1], "77")
        status = self.client.get("/api/tracking", headers=headers).json()
        self.assertEqual(status["anilist"], {"connected": True, "account": "Kai"})
        self.assertFalse(status["mal"]["connected"])

    def test_progress_only_moves_forward(self):
        calls = []

        async def fake(token, query, variables):
            calls.append(variables)
            return {"MediaList": {"progress": 5}} if "progress }" in query else {}

        with patch.object(tracking, "_anilist", side_effect=fake):
            asyncio.run(tracking._anilist_progress("t", "77", 154587, 3, 28))
            self.assertEqual(len(calls), 1)  # looked, and left it at 5
            asyncio.run(tracking._anilist_progress("t", "77", 154587, 7, 28))
        self.assertEqual(calls[-1], {"m": 154587, "p": 7, "s": "CURRENT"})

    def test_old_plaintext_tokens_get_sealed(self):
        headers, user_id = self.sign_up()
        with accounts._db() as conn:
            conn.execute("INSERT INTO tracking (user_id, service, token, refresh, expires_at, account_name)"
                         " VALUES (?, 'mal', 'plain-access', 'plain-refresh', 0, 'Kai')", (user_id,))
        self.assertEqual(tracking.seal_stored_tokens(), 1)
        token, refresh = sqlite3.connect(accounts.DB_PATH).execute("SELECT token, refresh FROM tracking").fetchone()
        self.assertEqual((secretbox.unseal(token), secretbox.unseal(refresh)), ("plain-access", "plain-refresh"))
        self.assertEqual(tracking.seal_stored_tokens(), 0)


class PartyTest(unittest.TestCase):
    def setUp(self):
        for name, value in [("_rooms", {}), ("_per_ip", {})]:
            p = patch.object(party, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def test_state_and_chat_reach_the_others(self):
        with self.client.websocket_connect("/ws/party/ABCD12?name=Kai") as a:
            hello = a.receive_json()
            self.assertEqual((hello["type"], hello["you"], hello["state"]), ("hello", "Kai", None))
            with self.client.websocket_connect("/ws/party/ABCD12?name=Kai") as b:
                hello_b = b.receive_json()
                # Same name in the same room: told apart.
                self.assertEqual(hello_b["you"], "Kai (2)")
                self.assertEqual(a.receive_json()["joined"], "Kai (2)")
                a.send_json({"type": "state", "anime": "154587", "ep": 3, "category": "sub", "playing": True, "t": 61.5})
                got = b.receive_json()
                self.assertEqual(got["type"], "state")
                self.assertEqual((got["state"]["ep"], got["state"]["t"], got["state"]["by"]), (3, 61.5, "Kai"))
                self.assertIn("now", got)
                b.send_json({"type": "chat", "text": "hi"})
                self.assertEqual(a.receive_json()["text"], "hi")

    def test_chat_is_rate_limited(self):
        with self.client.websocket_connect("/ws/party/RATE01?name=Spam") as a:
            a.receive_json()
            for i in range(4):
                a.send_json({"type": "chat", "text": f"msg {i}"})
            texts = [a.receive_json()["text"] for _ in range(4)]
        self.assertIn("Slow down a little.", texts)

    def test_bad_codes_are_refused(self):
        with self.assertRaises(Exception):
            with self.client.websocket_connect("/ws/party/no!") as ws:
                ws.receive_json()


class ProxyCorsTest(unittest.TestCase):
    """A Chromecast fetches /proxy/* from its own origin; nothing else is opened up."""

    def setUp(self):
        self.client = TestClient(app)

    def test_preflight_and_responses_on_the_proxy_allow_any_origin(self):
        r = self.client.options("/proxy/m3u8?url=x", headers={"Origin": "https://cast.example"})
        self.assertEqual(r.status_code, 204)
        self.assertEqual(r.headers["access-control-allow-origin"], "*")
        self.assertIn("Range", r.headers["access-control-allow-headers"])
        with patch("app.main.httpx.AsyncClient.get", new=AsyncMock(side_effect=RuntimeError("offline"))):
            r = self.client.get("/proxy/subtitle?url=http%3A%2F%2Fexample.invalid%2Fa.vtt")
        self.assertEqual(r.headers["access-control-allow-origin"], "*")

    def test_other_routes_stay_same_origin(self):
        r = self.client.get("/api/push/key")
        self.assertNotIn("access-control-allow-origin", r.headers)


class HousekeepingTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location("housekeeping", ROOT / "scripts" / "housekeeping.py")
        assert spec is not None and spec.loader is not None
        self.hk: Any = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.hk)
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        self.root = pathlib.Path(storage.name)
        self.hk.ROOT = self.root
        self.hk.BACKUPS = self.root / "backups"

    def test_backs_up_rotates_and_prunes(self):
        (self.root / "data" / "releases").mkdir(parents=True)
        (self.root / "logs").mkdir()
        db = sqlite3.connect(self.root / "data" / "aniverse.db")
        db.execute("CREATE TABLE t (x)")
        db.execute("INSERT INTO t VALUES (1)")
        db.commit()
        db.close()
        self.assertEqual(len(self.hk.backup(False)), 1)
        copy = next((self.root / "backups").glob("*/aniverse.db"))
        self.assertEqual(sqlite3.connect(copy).execute("SELECT x FROM t").fetchone(), (1,))

        log = self.root / "logs" / "frontend.log"
        log.write_text("x" * 100)
        self.hk.LOG_LIMIT = 10
        self.hk.rotate_logs(False)
        self.assertEqual(log.stat().st_size, 0)
        self.assertEqual((self.root / "logs" / "frontend.log.1").read_text(), "x" * 100)

        rel = self.root / "data" / "releases"
        for code in range(10, 16):
            (rel / f"aniverse-{code}-abc.apk").write_text("apk")
        (rel / "current.json").write_text(json.dumps({"file": "aniverse-11-abc.apk"}))
        with patch.dict(os.environ, {"ANIVERSE_KEEP_APKS": "3"}):
            self.hk.prune_releases(False)
        left = sorted(p.name for p in rel.glob("*.apk"))
        # The newest three, plus the current one however old.
        self.assertEqual(left, ["aniverse-11-abc.apk", "aniverse-13-abc.apk", "aniverse-14-abc.apk", "aniverse-15-abc.apk"])


if __name__ == "__main__":
    unittest.main()
