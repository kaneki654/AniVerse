"""Release checks use temporary files; no real release or account data changes."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import main
from scripts import publish_apk as publisher


class MobileReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "build.apk"
        self.source.write_bytes(b"signed apk bytes")
        self.releases = self.root / "releases"
        self.metadata = {
            "package": publisher.EXPECTED_PACKAGE, "versionName": "1.5.1",
            "versionCode": 12, "signingSha256": ["a" * 64],
        }
        self.inspect = patch.object(publisher, "inspect_apk", side_effect=lambda *_: dict(self.metadata))
        self.inspect.start()
        self.addCleanup(self.inspect.stop)
        self.directory = patch.object(main, "_RELEASES_DIR", self.releases)
        self.directory.start()
        self.addCleanup(self.directory.stop)
        self.client = TestClient(main.app)

    def publish(self):
        return publisher.publish_apk(self.source, self.releases, "aapt", "apksigner")

    def test_only_published_bytes_are_advertised_and_served(self):
        before = self.client.get("/app/version.json")
        self.assertFalse(before.json()["available"])
        self.assertEqual(self.client.get("/app/aniverse.apk").status_code, 404)
        release = self.publish()
        self.source.write_bytes(b"next build in progress")
        response = self.client.get("/app/version.json")
        self.assertEqual(response.json(), {
            "available": True, "versionName": "1.5.1", "versionCode": 12,
            "url": "/app/aniverse.apk", "size": len(b"signed apk bytes"), "sha256": release["sha256"],
        })
        self.assertIn("no-store", response.headers["cache-control"])
        download = self.client.get(response.json()["url"])
        self.assertEqual(download.content, b"signed apk bytes")
        self.assertIn("no-store", download.headers["cache-control"])

    def test_per_cpu_builds_are_offered_to_apps_that_say_their_cpu(self):
        arm = self.root / "app-arm64-v8a-release.apk"
        arm.write_bytes(b"arm64 build")

        def inspect(path, *_):
            meta = dict(self.metadata)
            meta["nativeCode"] = ["arm64-v8a"] if Path(path).read_bytes() == b"arm64 build" else ["arm64-v8a", "x86_64"]
            return meta

        with patch.object(publisher, "inspect_apk", side_effect=inspect):
            release = publisher.publish_apk(self.source, self.releases, "aapt", "apksigner", splits=[arm])
        self.assertEqual(set(release["abis"]), {"arm64-v8a"})
        old_app = self.client.get("/app/version.json").json()
        self.assertEqual((old_app["url"], old_app["size"]), ("/app/aniverse.apk", len(b"signed apk bytes")))
        new_app = self.client.get("/app/version.json", params={"abi": "arm64-v8a"}).json()
        self.assertEqual((new_app["url"], new_app["size"]), ("/app/aniverse.apk?abi=arm64-v8a", len(b"arm64 build")))
        self.assertEqual(self.client.get(new_app["url"]).content, b"arm64 build")
        # A CPU nobody built for gets the universal APK.
        self.assertEqual(self.client.get("/app/aniverse.apk", params={"abi": "mips"}).content, b"signed apk bytes")

    def test_a_split_from_another_release_is_refused(self):
        arm = self.root / "app-arm64-v8a-release.apk"
        arm.write_bytes(b"older arm64 build")

        def inspect(path, *_):
            meta = dict(self.metadata)
            if Path(path).read_bytes() == b"older arm64 build":
                meta.update(versionCode=11, nativeCode=["arm64-v8a"])
            return meta

        with patch.object(publisher, "inspect_apk", side_effect=inspect):
            with self.assertRaises(ValueError):
                publisher.publish_apk(self.source, self.releases, "aapt", "apksigner", splits=[arm])
        self.assertFalse((self.releases / "current.json").exists())
        self.assertEqual(list(self.releases.glob("*.apk")), [])

    def test_failed_signature_leaves_previous_publication_intact(self):
        self.publish()
        previous = (self.releases / "current.json").read_bytes()
        with patch.object(publisher, "inspect_apk", side_effect=ValueError("Invalid APK signature")):
            with self.assertRaises(ValueError):
                self.publish()
        self.assertEqual((self.releases / "current.json").read_bytes(), previous)
        self.assertEqual(len(list(self.releases.iterdir())), 2)

    def test_incompatible_or_non_increasing_build_keeps_previous_release(self):
        self.publish()
        previous = (self.releases / "current.json").read_bytes()
        for mutation in (
            {"versionCode": 11},
            {"versionCode": 13, "signingSha256": ["b" * 64]},
            {"versionCode": 13, "package": "com.example.other"},
        ):
            with self.subTest(mutation=mutation):
                original = self.metadata.copy()
                self.metadata.update(mutation)
                with self.assertRaises(ValueError):
                    self.publish()
                self.metadata = original
                self.assertEqual((self.releases / "current.json").read_bytes(), previous)
        self.source.write_bytes(b"changed without version bump")
        with self.assertRaises(ValueError):
            self.publish()
        self.assertEqual((self.releases / "current.json").read_bytes(), previous)

    def test_new_release_switches_manifest_and_retains_previous_apk(self):
        old = self.publish()
        self.metadata.update(versionCode=13, versionName="1.5.2")
        self.source.write_bytes(b"new signed APK")
        new = self.publish()
        self.assertEqual(self.client.get("/app/version.json").json()["versionCode"], 13)
        self.assertEqual(self.client.get("/app/aniverse.apk").content, b"new signed APK")
        self.assertTrue((self.releases / old["file"]).is_file())
        self.assertNotEqual(old["file"], new["file"])

    def test_missing_truncated_or_unsafe_artifact_is_unavailable(self):
        release = self.publish()
        apk = self.releases / release["file"]
        for change in ("truncated", "missing", "traversal", "invalid json"):
            with self.subTest(change=change):
                if change == "truncated":
                    apk.write_bytes(b"x")
                elif change == "missing":
                    apk.unlink()
                elif change == "traversal":
                    release["file"] = "../build.apk"
                    (self.releases / "current.json").write_text(json.dumps(release))
                else:
                    (self.releases / "current.json").write_text("{")
                self.assertFalse(self.client.get("/app/version.json").json()["available"])
                self.assertEqual(self.client.get("/app/aniverse.apk").status_code, 404)

    def publish_rust(self, **details):
        self.metadata.update(package="app.aniverse.rust", versionName="0.1.0", versionCode=1)
        return publisher.publish_apk(self.source, self.releases, "aapt", "apksigner",
                                     edition="rust", details=details)

    def test_rust_edition_has_its_own_manifest_download_and_details(self):
        self.metadata["nativeCode"] = ["arm64-v8a"]
        release = self.publish_rust(highlights=["Opens in 0.4 s"], measured="Median of 5 cold starts",
                                    note="Preview")
        self.assertEqual(publisher.inspect_apk.call_args.args[3], "app.aniverse.rust")
        self.assertTrue(release["file"].startswith("aniverse-rust-1-"))
        self.assertTrue((self.releases / "rust.json").is_file())
        # The original app's update check never sees the Rust build.
        self.assertFalse((self.releases / "current.json").exists())
        self.assertFalse(self.client.get("/app/version.json").json()["available"])
        self.assertEqual(self.client.get("/app/aniverse.apk").status_code, 404)
        info = self.client.get("/app/rust/version.json")
        self.assertIn("no-store", info.headers["cache-control"])
        self.assertEqual(info.json(), {
            "available": True, "versionName": "0.1.0", "versionCode": 1, "url": "/app/aniverse-rust.apk",
            "size": len(b"signed apk bytes"), "sha256": release["sha256"], "nativeCode": ["arm64-v8a"],
            "highlights": ["Opens in 0.4 s"], "measured": "Median of 5 cold starts", "note": "Preview",
        })
        download = self.client.get(info.json()["url"])
        self.assertEqual(download.content, b"signed apk bytes")
        self.assertIn("AniVerse-Rust.apk", download.headers["content-disposition"])

    def test_both_editions_are_served_side_by_side(self):
        original = self.publish()
        rust = self.publish_rust()
        self.assertEqual(self.client.get("/app/version.json").json()["versionCode"], original["versionCode"])
        self.assertEqual(self.client.get("/app/rust/version.json").json()["versionCode"], rust["versionCode"])
        self.assertNotEqual(original["file"], rust["file"])

    def test_rust_details_that_would_not_fit_are_refused(self):
        for details in ({"highlights": ["x"] * 7}, {"highlights": ["x" * 141]}, {"highlights": [" "]},
                        {"note": "x" * 241}, {"measured": "x" * 241}):
            with self.subTest(details=details):
                with self.assertRaises(ValueError):
                    self.publish_rust(**details)
        self.assertFalse(self.client.get("/app/rust/version.json").json()["available"])
        self.assertEqual(self.client.get("/app/aniverse-rust.apk").status_code, 404)

    def test_unsound_rust_manifest_extras_are_dropped(self):
        release = self.publish_rust()
        release.update(highlights=["ok", 5, "x" * 500], nativeCode="arm64-v8a", note=["not text"])
        (self.releases / "rust.json").write_text(json.dumps(release))
        info = self.client.get("/app/rust/version.json").json()
        self.assertTrue(info["available"])
        self.assertEqual((info["highlights"], info["nativeCode"], info["note"], info["measured"]),
                         (["ok"], [], "", ""))


class InspectApkTests(unittest.TestCase):
    def test_reads_verified_apk_metadata(self):
        outputs = [
            subprocess.CompletedProcess([], 0, stdout="Signer #1 certificate SHA-256 digest: " + "a" * 64),
            subprocess.CompletedProcess([], 0, stdout="package: name='com.example.aniverse_mobile' versionCode='12' versionName='1.5.1'\n"),
        ]
        with patch.object(publisher.subprocess, "run", side_effect=outputs) as run:
            result = publisher.inspect_apk(Path("build.apk"), "aapt", "apksigner", publisher.EXPECTED_PACKAGE)
        self.assertEqual(result["versionCode"], 12)
        self.assertEqual(result["versionName"], "1.5.1")
        self.assertEqual(run.call_args_list[0].args[0], ["apksigner", "verify", "--print-certs", "build.apk"])

    def test_rejects_wrong_package_and_unsigned_apk(self):
        for signer, package in (("a" * 64, "com.example.other"), ("", publisher.EXPECTED_PACKAGE)):
            with self.subTest(signer=signer, package=package):
                outputs = [
                    subprocess.CompletedProcess([], 0, stdout="Signer #1 certificate SHA-256 digest: " + signer),
                    subprocess.CompletedProcess([], 0, stdout=f"package: name='{package}' versionCode='12' versionName='1.5.1'"),
                ]
                with patch.object(publisher.subprocess, "run", side_effect=outputs):
                    with self.assertRaises(ValueError):
                        publisher.inspect_apk(Path("build.apk"), "aapt", "apksigner", publisher.EXPECTED_PACKAGE)


if __name__ == "__main__":
    unittest.main()
