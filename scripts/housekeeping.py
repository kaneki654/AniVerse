"""Daily housekeeping for a running AniVerse: database backups, log rotation,
and pruning old published APKs.

    python3 scripts/housekeeping.py            # once
    python3 scripts/housekeeping.py --dry-run  # say what it would do

start_all.sh runs it when the servers start and once a day after that.

- Backups: every SQLite database (data/aniverse.db -- accounts, history, My
  List, tracking -- and AniVerseApiUrl/data/*.db, the skip times) is copied
  with SQLite's online backup, which is safe while the servers are writing,
  into backups/YYYY-MM-DD/. The newest 14 days are kept.
- Logs: logs/*.log over 10 MB are copied to .log.1 (older ones shift to .2,
  .3) and then emptied in place. The servers append to them, so emptying is
  safe and they carry on writing.
- Releases: data/releases keeps the newest 3 APKs; the one current.json
  points at is never removed.
"""
import argparse
import datetime
import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKUPS = ROOT / "backups"
KEEP_DAYS = 14
LOG_LIMIT = 10 * 1024 * 1024
LOG_KEEP = 3
# Old APKs kept besides the one published now; 0 keeps every one.
# ANIVERSE_KEEP_APKS in .aniverse_env changes it.
KEEP_APKS_DEFAULT = 5
DISK_LOW = 0.10


def keep_apks() -> int:
    try:
        return max(0, int(os.environ.get("ANIVERSE_KEEP_APKS", KEEP_APKS_DEFAULT)))
    except ValueError:
        return KEEP_APKS_DEFAULT


def databases() -> list[Path]:
    return [p for p in [ROOT / "data" / "aniverse.db", *sorted((ROOT / "AniVerseApiUrl" / "data").glob("*.db"))] if p.is_file()]


def backup(dry: bool) -> list[str]:
    done = []
    day = BACKUPS / datetime.date.today().isoformat()
    for db in databases():
        target = day / db.name
        done.append(f"backup {db.relative_to(ROOT)} -> {target.relative_to(ROOT)}")
        if dry:
            continue
        day.mkdir(parents=True, exist_ok=True)
        tmp = target.with_suffix(".tmp")
        src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        dst = sqlite3.connect(tmp)
        try:
            src.backup(dst)
        finally:
            dst.close()
            src.close()
        tmp.replace(target)
    # Keep the newest KEEP_DAYS days.
    days = sorted(p for p in BACKUPS.glob("????-??-??") if p.is_dir()) if BACKUPS.exists() else []
    for old in days[:-KEEP_DAYS]:
        done.append(f"remove old backup {old.relative_to(ROOT)}")
        if not dry:
            shutil.rmtree(old, ignore_errors=True)
    return done


def rotate_logs(dry: bool) -> list[str]:
    done = []
    for log in sorted((ROOT / "logs").glob("*.log")):
        if log.stat().st_size <= LOG_LIMIT:
            continue
        done.append(f"rotate {log.relative_to(ROOT)} ({log.stat().st_size // 1024 // 1024} MB)")
        if dry:
            continue
        for i in range(LOG_KEEP - 1, 0, -1):
            older = log.with_name(f"{log.name}.{i}")
            if older.exists():
                older.replace(log.with_name(f"{log.name}.{i + 1}"))
        shutil.copyfile(log, log.with_name(f"{log.name}.1"))
        # Emptied, not replaced: the servers keep their file open and append.
        with open(log, "r+") as f:
            f.truncate(0)
    return done


def prune_releases(dry: bool) -> list[str]:
    folder = ROOT / "data" / "releases"
    if not folder.is_dir():
        return []
    try:
        current = json.loads((folder / "current.json").read_text()).get("file")
    except (OSError, ValueError):
        current = None

    def code(p: Path) -> int:
        try:
            return int(p.name.split("-")[1])
        except (IndexError, ValueError):
            return -1

    apks = sorted(folder.glob("aniverse-*.apk"), key=code)
    keep = keep_apks()
    if keep == 0:
        return []
    done = []
    for apk in apks[:-keep]:
        if apk.name == current:
            continue
        done.append(f"remove old release {apk.name}")
        if not dry:
            apk.unlink(missing_ok=True)
    return done


def check_disk(dry: bool) -> list[str]:
    u = shutil.disk_usage(ROOT)
    free = u.free / u.total if u.total else 0.0
    line = f"disk: {u.free / 1e9:.1f} GB free of {u.total / 1e9:.0f} GB ({100 * free:.0f}%)"
    if free < DISK_LOW:
        line = "WARNING " + line + " -- under 10%; saves fail when it reaches zero"
    return [line]


def main() -> int:
    ap = argparse.ArgumentParser(description="Back up databases, rotate logs, prune old APKs.")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    for step in (check_disk, backup, rotate_logs, prune_releases):
        try:
            for line in step(args.dry_run):
                print(f"  {line}")
        except Exception as e:  # one failing step must not stop the others
            print(f"  {step.__name__} failed: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
