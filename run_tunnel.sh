#!/usr/bin/env bash
# Exposes the AniVerse web app (port 8000) on a public https URL — mirrors
# run_tunnel.bat.
#
# The API is NOT tunnelled separately: the web app proxies it under
# /api/anime/*, so one tunnel covers both.
#
# Free trycloudflare URLs are assigned fresh on every start. The Android app
# reads the current address from the install site rather than a compiled-in
# constant, so a restart only needs that republished — no rebuild, no reinstall:
#   python aniverse_site/build_site.py --host https://<new-url>.trycloudflare.com
#   cd aniverse_site && vercel deploy --prod
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="$ROOT/logs/tunnel.log"
mkdir -p "$ROOT/logs"

# Search order: an explicit CLOUDFLARED override, then PATH (under both names,
# since git-bash needs the .exe), then the usual install locations for Linux,
# macOS and Windows.
CF=""
if [ -n "${CLOUDFLARED:-}" ] && [ -x "${CLOUDFLARED}" ]; then
  CF="${CLOUDFLARED}"
else
  for c in cloudflared cloudflared.exe; do
    if command -v "$c" >/dev/null 2>&1; then CF="$(command -v "$c")"; break; fi
  done
fi
if [ -z "$CF" ]; then
  for c in     /usr/local/bin/cloudflared     /usr/bin/cloudflared     /opt/cloudflared/cloudflared     /snap/bin/cloudflared     /opt/homebrew/bin/cloudflared     "${HOME:-}/.local/bin/cloudflared"     "${HOME:-}/bin/cloudflared"     /c/Tools/cloudflared.exe     "/c/Program Files/cloudflared/cloudflared.exe"     "/c/Program Files (x86)/cloudflared/cloudflared.exe"
  do
    [ -x "$c" ] && { CF="$c"; break; }
  done
fi

if [ -z "$CF" ]; then
  cat <<'MSG'
cloudflared was not found.

Install it, or drop the binary on your PATH:
  Debian/Ubuntu  sudo apt install cloudflared
  Arch           sudo pacman -S cloudflared
  macOS          brew install cloudflared
  Manual         https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
MSG
  exit 1
fi

echo "Using $CF"
echo "Starting Cloudflare tunnel to http://localhost:8000 ..."
echo "The public URL appears below and in $LOG"
echo

# tee so the URL is visible now and recoverable later; cloudflared writes its
# banner to stderr, hence the redirect.
"$CF" tunnel --url http://localhost:8000 2>&1 | tee "$LOG"
