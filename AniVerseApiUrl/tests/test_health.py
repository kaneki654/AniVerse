"""The status page's history survives a restart (app/core/health.py)."""

import pathlib
import tempfile
import time
import unittest

from app.core import health


class HealthPersistenceTest(unittest.TestCase):
    def setUp(self):
        self.saved = (list(health._attempts), list(health._resolves))
        health._attempts.clear()
        health._resolves.clear()
        self.addCleanup(self.restore)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.path = pathlib.Path(tmp.name) / "health.json"

    def restore(self):
        health._attempts.clear()
        health._resolves.clear()
        health._attempts.extend(self.saved[0])
        health._resolves.extend(self.saved[1])

    def test_save_then_load_keeps_the_last_day(self):
        health.record_attempt("ZokoAnimeProvider", "ok", 1.2)
        health.record_attempt("GogoAnimeProvider", "error", 4.0, "timed out")
        health.record_resolve(True, "154587", 3, "sub", "", 2.5)
        # Something from two days ago is not worth keeping.
        health._attempts.appendleft((time.time() - 2 * 86400, "Old", "ok", 1.0, ""))
        health.save(self.path)
        health._attempts.clear()
        health._resolves.clear()
        health.load(self.path)
        s = health.summary()
        self.assertEqual(sorted(p["name"] for p in s["providers"]), ["GogoAnimeProvider", "ZokoAnimeProvider"])
        self.assertEqual(s["coverage"]["playable"], 1)

    def test_a_missing_or_broken_file_is_ignored(self):
        health.load(self.path)
        self.path.write_text("{not json")
        health.load(self.path)
        self.assertEqual(health.summary()["coverage"]["total"], 0)


if __name__ == "__main__":
    unittest.main()
