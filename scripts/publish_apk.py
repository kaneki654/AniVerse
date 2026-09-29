"""Verify and publish a finished Android release without exposing partial builds.

Run from the repository root:
    python scripts/publish_apk.py aniverse_mobile/build/app/outputs/flutter-apk/app-release.apk
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_RELEASES_DIR = ROOT / "data" / "releases"
EXPECTED_PACKAGE = "com.example.aniverse_mobile"


def _fsync_directory(path):
    """Flush a directory entry to disk where the platform allows it.

    Windows refuses to open a directory this way (PermissionError). That came
    after os.replace() had already switched current.json, so a successful
    publish was reported as "Publication failed" -- the release was live while
    the tool said it was not. The rename itself is already atomic there.
    """
    if os.name == "nt":
        return
    directory_fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def find_android_tool(name):
    """Use PATH or the installed Android SDK's newest build-tools directory."""
    on_path = shutil.which(name)
    if on_path:
        return Path(on_path)
    roots = [os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME")]
    properties = ROOT / "aniverse_mobile" / "android" / "local.properties"
    if properties.is_file():
        roots.extend(line.partition("=")[2].strip() for line in properties.read_text().splitlines()
                     if line.startswith("sdk.dir="))
    roots.append(str(Path.home() / "Android" / "Sdk"))
    for sdk_root in filter(None, roots):
        versions = list((Path(sdk_root) / "build-tools").glob("*"))
        versions.sort(key=lambda p: tuple(map(int, re.findall(r"\d+", p.name))), reverse=True)
        # The SDK ships aapt.exe and apksigner.bat on Windows; looking only for
        # the bare name meant the tool could never find them there.
        names = [name, name + ".exe", name + ".bat"] if os.name == "nt" else [name]
        for version in versions:
            for filename in names:
                candidate = version / filename
                if candidate.is_file() and os.access(candidate, os.X_OK):
                    return candidate
    raise ValueError(f"Cannot find {name}; set ANDROID_SDK_ROOT or pass --{name}.")


def inspect_apk(apk, aapt, apksigner, expected_package):
    """Read actual APK metadata, and require a valid Android signature."""
    signature = subprocess.run(
        [str(apksigner), "verify", "--print-certs", str(apk)],
        check=True, capture_output=True, text=True,
    ).stdout
    signers = sorted(set(re.findall(
        r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})", signature,
    )))
    if not signers:
        raise ValueError("APK has no verified signing certificate.")
    badging = subprocess.run(
        [str(aapt), "dump", "badging", str(apk)],
        check=True, capture_output=True, text=True,
    ).stdout
    package_line = next((line for line in badging.splitlines() if line.startswith("package:")), "")
    fields = dict(re.findall(r"(\w+)='([^']*)'", package_line))
    if fields.get("name") != expected_package:
        raise ValueError(f"Expected package {expected_package}, got {fields.get('name')!r}.")
    code = int(fields.get("versionCode", "0"))
    name = fields.get("versionName", "")
    if code <= 0 or not name:
        raise ValueError("APK must have a positive versionCode and a versionName.")
    return {"package": expected_package, "versionName": name, "versionCode": code,
            "signingSha256": [signer.lower() for signer in signers]}


def publish_apk(source, releases_dir, aapt, apksigner, expected_package=EXPECTED_PACKAGE):
    """Publish an immutable APK first, then atomically replace current.json."""
    source, releases_dir = Path(source), Path(releases_dir)
    if not source.is_file():
        raise ValueError(f"APK not found: {source}")
    releases_dir.mkdir(parents=True, exist_ok=True)
    staged_path = None
    manifest_path = None
    try:
        # Inspect the staged copy so a concurrent Flutter build cannot change
        # the file between verification and publication.
        with tempfile.NamedTemporaryFile(dir=releases_dir, suffix=".apk", delete=False) as staged:
            staged_path = Path(staged.name)
            with source.open("rb") as original:
                shutil.copyfileobj(original, staged)
            staged.flush()
            os.fsync(staged.fileno())
        release = inspect_apk(staged_path, aapt, apksigner, expected_package)
        with staged_path.open("rb") as apk_bytes:
            digest = hashlib.file_digest(apk_bytes, "sha256").hexdigest()
        release.update({"file": f"aniverse-{release['versionCode']}-{digest[:16]}.apk",
                        "size": staged_path.stat().st_size, "sha256": digest})
        current_path = releases_dir / "current.json"
        if current_path.exists():
            previous = json.loads(current_path.read_text())
            if (previous["package"] != release["package"]
                    or previous["signingSha256"] != release["signingSha256"]):
                raise ValueError("Package or signing key differs from the published release; refusing an incompatible update.")
            if release["versionCode"] < previous["versionCode"]:
                raise ValueError("Refusing to publish a lower versionCode.")
            if release["versionCode"] == previous["versionCode"] and release["sha256"] != previous["sha256"]:
                raise ValueError("Changed APK must have a higher versionCode.")
        destination = releases_dir / release["file"]
        os.replace(staged_path, destination)
        staged_path = None
        with tempfile.NamedTemporaryFile(mode="w", dir=releases_dir, suffix=".json", delete=False) as manifest:
            manifest_path = Path(manifest.name)
            json.dump(release, manifest, indent=2)
            manifest.write("\n")
            manifest.flush()
            os.fsync(manifest.fileno())
        os.replace(manifest_path, current_path)
        manifest_path = None
        _fsync_directory(releases_dir)
        return release
    finally:
        for temporary in (staged_path, manifest_path):
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--releases-dir", type=Path, default=DEFAULT_RELEASES_DIR)
    parser.add_argument("--aapt", type=Path)
    parser.add_argument("--apksigner", type=Path)
    args = parser.parse_args()
    try:
        release = publish_apk(args.apk, args.releases_dir,
                              args.aapt or find_android_tool("aapt"),
                              args.apksigner or find_android_tool("apksigner"))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"Publication failed: {exc}\n")
    print(json.dumps(release, indent=2))


if __name__ == "__main__":
    main()
