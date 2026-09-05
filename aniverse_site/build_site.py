"""Assemble the Vercel install site.

Copies the freshly built APK and the launcher icon next to index.html and writes
a version.json the page reads, so the published version and size can never drift
from the binary actually being served.

The APK and icon are deliberately not committed (see .gitignore) -- this script
regenerates them from the Flutter build output.

Usage:
    python aniverse_site/build_site.py [--host https://<tunnel>.trycloudflare.com]
"""
import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

APK_SRC = os.path.join(
    ROOT, "aniverse_mobile", "build", "app", "outputs", "flutter-apk", "app-release.apk")
ICON_SRC = os.path.join(
    ROOT, "aniverse_mobile", "android", "app", "src", "main", "res",
    "mipmap-xxxhdpi", "ic_launcher.png")
PUBSPEC = os.path.join(ROOT, "aniverse_mobile", "pubspec.yaml")
API_SERVICE = os.path.join(
    ROOT, "aniverse_mobile", "lib", "services", "api_service.dart")


def pubspec_version():
    """(versionName, versionCode) from `version: 1.2.3+45`."""
    with open(PUBSPEC, encoding="utf-8") as f:
        for line in f:
            if line.startswith("version:"):
                raw = line.split(":", 1)[1].strip()
                name, _, code = raw.partition("+")
                return name.strip(), int(code or 1)
    raise SystemExit("no version: line in pubspec.yaml")


def baked_host():
    """The server address compiled into the APK, so the page shows the same one."""
    with open(API_SERVICE, encoding="utf-8") as f:
        m = re.search(r"defaultHost\s*=\s*\n?\s*'([^']+)'", f.read())
    return m.group(1) if m else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", help="override the server address shown on the page")
    args = ap.parse_args()

    if not os.path.exists(APK_SRC):
        raise SystemExit("APK not found -- run: flutter build apk --release")

    shutil.copy2(APK_SRC, os.path.join(HERE, "aniverse.apk"))
    shutil.copy2(ICON_SRC, os.path.join(HERE, "icon.png"))

    name, code = pubspec_version()
    payload = {
        "versionName": name,
        "versionCode": code,
        "url": "/aniverse.apk",
        "size": os.path.getsize(APK_SRC),
        "available": True,
        "host": args.host or baked_host(),
    }
    with open(os.path.join(HERE, "version.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")

    print("site ready in %s" % HERE)
    print("  apk    %.1f MB" % (payload["size"] / 1048576))
    print("  build  %s+%s" % (name, code))
    print("  host   %s" % payload["host"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
