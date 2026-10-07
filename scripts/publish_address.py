"""Publish the server's current public address where the app can always find it.

A quick Cloudflare tunnel gets a new random URL on every start, and the app has
to learn it somehow. This writes `discovery/host.json` straight to the GitHub
repository (through the GitHub API, with the `gh` CLI), which the app reads from
raw.githubusercontent.com. Nothing in the local checkout changes: no commit, no
branch switch, nothing to pull before you can push your own work.

    python3 scripts/publish_address.py --host https://abc.trycloudflare.com
    python3 scripts/publish_address.py --host ... --dry-run   # show, don't send

Needs `gh` signed in (`gh auth login`) with push access to the repository.
start_all.sh runs this after the tunnel is up when ANIVERSE_PUBLISH_GIT=1.
"""
import argparse
import base64
import datetime
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = "discovery/host.json"


def repo_slug() -> str:
    """owner/name from ANIVERSE_DISCOVERY_REPO or the origin remote."""
    slug = os.environ.get("ANIVERSE_DISCOVERY_REPO", "").strip()
    if slug:
        return slug
    url = subprocess.run(["git", "-C", ROOT, "remote", "get-url", "origin"],
                         capture_output=True, text=True, check=False).stdout.strip()
    m = re.search(r"github\.com[/:]([^/]+/[^/]+?)(?:\.git)?$", url)
    if not m:
        raise SystemExit(f"origin is not a GitHub repository ({url or 'no origin'}); set ANIVERSE_DISCOVERY_REPO=owner/name")
    return m.group(1)


def gh(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", "api", *args], input=stdin, capture_output=True, text=True, check=False)


def main() -> int:
    ap = argparse.ArgumentParser(description="Publish the server's public address to discovery/host.json on GitHub.")
    ap.add_argument("--host", required=True, help="the public https:// address of the website server")
    ap.add_argument("--branch", default=os.environ.get("ANIVERSE_DISCOVERY_BRANCH", "main"))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    host = args.host.strip().rstrip("/")
    if not re.match(r"^https://[\w.-]+(:\d+)?$", host):
        raise SystemExit(f"not an https origin: {host}")
    body = {"host": host, "updated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    text = json.dumps(body, indent=2) + "\n"
    slug = repo_slug()
    if args.dry_run:
        print(f"would write {slug}:{args.branch}/{PATH}:\n{text}")
        return 0
    if not shutil.which("gh"):
        print("  gh (GitHub CLI) is not installed, so the address was not published.", file=sys.stderr)
        print("  Install it, run `gh auth login`, and start again.", file=sys.stderr)
        return 1

    endpoint = f"repos/{slug}/contents/{PATH}"
    # The current file's sha is needed to replace it; none means it is created.
    current = gh(f"{endpoint}?ref={args.branch}")
    sha = None
    if current.returncode == 0:
        try:
            existing = json.loads(current.stdout)
            sha = existing.get("sha")
            if json.loads(base64.b64decode(existing.get("content", "")) or b"{}").get("host") == host:
                print(f"  {PATH} already says {host}")
                return 0
        except (ValueError, TypeError):
            sha = None
    payload = {"message": f"Server address: {host}", "content": base64.b64encode(text.encode()).decode(),
               "branch": args.branch, **({"sha": sha} if sha else {})}
    r = gh("-X", "PUT", endpoint, "--input", "-", stdin=json.dumps(payload))
    if r.returncode != 0:
        print(f"  publishing failed: {(r.stderr or r.stdout).strip()[:300]}", file=sys.stderr)
        return 1
    print(f"  published {host} to github.com/{slug} ({PATH})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
