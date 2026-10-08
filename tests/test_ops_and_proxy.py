"""
The server keeping itself safe and healthy: the proxy only fetches hosts the
server handed out, the disk-full message, error reports from clients, the
login limits, how many old APKs housekeeping keeps, and the sweep summary.
"""

import errno
import importlib.util
import json
import os
import pathlib
import sqlite3
import tempfile
import unittest
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import accounts, ops, proxy_hosts
from app.main import app

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _load_script(name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module: Any = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _Isolated(unittest.TestCase):
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
            (ops, "ERRORS_LOG", self.dir / "client_errors.log"),
            (ops, "LOG_DIR", self.dir),
            (ops, "SWEEP_FILE", self.dir / "sweep.json"),
            (ops, "_hits", {}),
        ]:
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)
        proxy_hosts.forget_all()
        self.addCleanup(proxy_hosts.forget_all)
        self.client = TestClient(app)
        self.addCleanup(self.client.close)


class ProxyHostsTest(_Isolated):
    def test_unknown_hosts_are_refused_on_every_proxy_route(self):
        target = "https://not-handed-out.example/x"
        for route in ("m3u8", "ts", "stream", "subtitle"):
            r = self.client.get(f"/proxy/{route}", params={"url": target})
            self.assertEqual(r.status_code, 403, route)
            # Still readable cross-origin, so a Chromecast sees the refusal.
            self.assertEqual(r.headers["access-control-allow-origin"], "*")

    def test_handed_out_hosts_are_allowed_and_survive_a_restart(self):
        proxy_hosts.allow("https://cdn.example/show/master.m3u8")
        self.assertTrue(proxy_hosts.allowed("https://CDN.example/other/seg1.ts"))
        self.assertFalse(proxy_hosts.allowed("https://cdn.example.evil/x"))
        proxy_hosts.forget_all()  # as after a restart: read back from the database
        self.assertTrue(proxy_hosts.allowed("https://cdn.example/seg2.ts"))

    def test_local_addresses_are_never_allowed(self):
        for url in ("http://127.0.0.1:8000/admin", "http://localhost/x", "http://192.168.1.10/x",
                    "http://[::1]/x", "http://169.254.169.254/latest", "file:///etc/passwd"):
            proxy_hosts.allow(url)
            self.assertFalse(proxy_hosts.allowed(url), url)

    def test_hosts_inside_a_rewritten_playlist_are_allowed(self):
        proxy_hosts.allow("https://cdn.example/master.m3u8")
        playlist = ("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example/k1\"\n"
                    "#EXTINF:6,\nhttps://segments.example/s1.ts\n#EXT-X-ENDLIST\n")
        upstream = MagicMock(status_code=200, text=playlist)
        with patch("app.main.httpx.AsyncClient.get", new=AsyncMock(return_value=upstream)):
            r = self.client.get("/proxy/m3u8", params={"url": "https://cdn.example/master.m3u8"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("/proxy/ts?url=https%3A%2F%2Fsegments.example", r.text)
        self.assertTrue(proxy_hosts.allowed("https://segments.example/s2.ts"))
        self.assertTrue(proxy_hosts.allowed("https://keys.example/k2"))


class DiskFullTest(unittest.TestCase):
    def test_a_save_that_fails_for_space_says_so(self):
        demo = FastAPI()
        ops.install(demo)

        @demo.get("/save")
        def save():
            raise sqlite3.OperationalError("database or disk is full")

        @demo.get("/write")
        def write():
            raise OSError(errno.ENOSPC, "No space left on device")

        @demo.get("/other")
        def other():
            raise sqlite3.OperationalError("no such table: x")

        client = TestClient(demo, raise_server_exceptions=False)
        for path in ("/save", "/write"):
            r = client.get(path)
            self.assertEqual(r.status_code, 507, path)
            self.assertIn("disk is full", r.json()["detail"])
        self.assertEqual(client.get("/other").status_code, 500)

    def test_disk_numbers(self):
        d = ops.disk()
        self.assertEqual(set(d), {"freeGb", "totalGb", "freePercent", "low"})
        self.assertLessEqual(d["freeGb"], d["totalGb"])


class ClientErrorsTest(_Isolated):
    def report(self, **extra):
        body = {"source": "app", "version": "1.11.0", "kind": "playback", "message": "no stream", "stack": "trace", **extra}
        return self.client.post("/api/client-errors", json=body)

    def test_reports_are_stored_without_ip_and_listed_without_stacks(self):
        self.assertEqual(self.report(where="watch").status_code, 204)
        row = json.loads(ops.ERRORS_LOG.read_text().splitlines()[0])
        self.assertEqual((row["source"], row["kind"], row["where"]), ("app", "playback", "watch"))
        self.assertNotIn("ip", row)
        status = self.client.get("/api/ops").json()
        self.assertEqual(status["clientErrors"]["last24h"], 1)
        self.assertNotIn("stack", status["clientErrors"]["latest"][0])

    def test_a_crash_loop_cannot_fill_the_disk(self):
        for _ in range(ops.ERRORS_PER_HOUR + 10):
            self.assertEqual(self.report().status_code, 204)
        self.assertEqual(len(ops.ERRORS_LOG.read_text().splitlines()), ops.ERRORS_PER_HOUR)

    def test_oversized_reports_are_rejected(self):
        self.assertEqual(self.report(message="x" * 5000).status_code, 422)

    def test_sweep_summary_shows_on_the_status_endpoint(self):
        self.assertIsNone(self.client.get("/api/ops").json()["sweep"])
        ops.SWEEP_FILE.write_text(json.dumps({"at": 1, "total": 4, "ok": 3, "servers": {"Zoko": 3},
                                              "failing": [{"id": 9, "ep": 2, "title": "X", "error": "none"}]}))
        sweep = self.client.get("/api/ops").json()["sweep"]
        self.assertEqual((sweep["percent"], sweep["failing"][0]["id"]), (75, 9))


class LoginLimitTest(_Isolated):
    def test_password_guessing_is_cut_off(self):
        self.client.post("/api/auth/register", json={"username": "Owner", "password": "right-password-1"})
        for _ in range(accounts.LOGIN_MAX_FAILURES):
            r = self.client.post("/api/auth/login", json={"username": "Owner", "password": "wrong-password"})
            self.assertEqual(r.status_code, 401)
        r = self.client.post("/api/auth/login", json={"username": "Owner", "password": "right-password-1"})
        self.assertEqual(r.status_code, 429)

    def test_mass_sign_up_is_cut_off(self):
        codes = [self.client.post("/api/auth/register", json={"username": f"bot{i}", "password": "pass-word-123"}).status_code
                 for i in range(accounts.REGISTER_MAX + 1)]
        self.assertEqual(codes[-1], 429)
        self.assertTrue(all(c == 200 for c in codes[:-1]))


class ReleaseRetentionTest(unittest.TestCase):
    def setUp(self):
        self.hk = _load_script("housekeeping")
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        self.hk.ROOT = pathlib.Path(storage.name)
        self.rel = self.hk.ROOT / "data" / "releases"
        self.rel.mkdir(parents=True)
        for code in range(10, 20):
            (self.rel / f"aniverse-{code}-abc.apk").write_text("apk")
        (self.rel / "current.json").write_text(json.dumps({"file": "aniverse-19-abc.apk"}))

    def left(self) -> list:
        return sorted(int(p.name.split("-")[1]) for p in self.rel.glob("*.apk"))

    def test_keeps_five_by_default(self):
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("ANIVERSE_KEEP_APKS", None)
            self.hk.prune_releases(False)
        self.assertEqual(self.left(), [15, 16, 17, 18, 19])

    def test_the_number_comes_from_the_environment_and_zero_keeps_all(self):
        with patch.dict(os.environ, {"ANIVERSE_KEEP_APKS": "0"}):
            self.hk.prune_releases(False)
        self.assertEqual(len(self.left()), 10)
        with patch.dict(os.environ, {"ANIVERSE_KEEP_APKS": "2"}):
            self.hk.prune_releases(False)
        self.assertEqual(self.left(), [18, 19])

    def test_a_release_counts_once_however_many_cpu_builds_it_has(self):
        for code in (18, 19):
            for abi in ("arm64-v8a", "armeabi-v7a"):
                (self.rel / f"aniverse-{code}-{abi}-abc.apk").write_text("apk")
        (self.rel / "current.json").write_text(json.dumps({
            "file": "aniverse-19-abc.apk", "abis": {"arm64-v8a": {"file": "aniverse-19-arm64-v8a-abc.apk"}}}))
        with patch.dict(os.environ, {"ANIVERSE_KEEP_APKS": "2"}):
            self.hk.prune_releases(False)
        left = sorted(p.name for p in self.rel.glob("*.apk"))
        self.assertEqual({int(n.split("-")[1]) for n in left}, {18, 19})
        self.assertEqual(len(left), 6)

    def test_disk_line_is_logged(self):
        line = self.hk.check_disk(False)[0]
        self.assertIn("GB free", line)


class SweepSummaryTest(unittest.TestCase):
    def test_summary_counts_servers_and_lists_failures(self):
        sweep = _load_script("sweep_playable")
        results = [
            {"id": 1, "ep": 3, "title": "A", "ok": True, "servers": ["Zoko", "Zoko", "Gogo"], "error": ""},
            {"id": 2, "ep": 1, "title": "B", "ok": True, "servers": ["Zoko"], "error": ""},
            {"id": 3, "ep": 7, "title": "C", "ok": False, "servers": [], "error": "no sources"},
        ]
        s = sweep.summarize(results)
        self.assertEqual((s["total"], s["ok"]), (3, 2))
        self.assertEqual(s["servers"], {"Zoko": 2, "Gogo": 1})
        self.assertEqual(s["failing"], [{"id": 3, "ep": 7, "title": "C", "error": "no sources"}])
        self.assertEqual(sweep.latest_aired({"nextAiringEpisode": {"episode": 5}}), 4)
        self.assertEqual(sweep.latest_aired({"episodes": 12, "nextAiringEpisode": None}), 12)


if __name__ == "__main__":
    unittest.main()
