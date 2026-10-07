#!/usr/bin/env bash
# One-time setup for a permanent server address: a named Cloudflare tunnel on a
# hostname in a domain you have on Cloudflare (a free plan is enough).
#
#   ./scripts/setup_named_tunnel.sh anime.example.com [tunnel-name]
#
# Quick tunnels get a new random trycloudflare.com URL on every start; a named
# tunnel keeps the same hostname for good, so phones never need to look a new
# one up. This logs cloudflared in (a browser page where you pick the domain),
# creates the tunnel, points the hostname at it, and saves the result in
# .aniverse_tunnel, which start_all.sh reads from then on.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-}"
NAME="${2:-aniverse}"

if [ -z "$HOST" ]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
HOST="${HOST#https://}"
HOST="${HOST%/}"

CF="$(command -v cloudflared || true)"
if [ -z "$CF" ]; then
  echo "cloudflared is not installed. Debian/Ubuntu: sudo apt install cloudflared" >&2
  exit 1
fi

if [ ! -f "${HOME}/.cloudflared/cert.pem" ]; then
  echo "==> Logging cloudflared in: pick the domain that $HOST belongs to."
  "$CF" tunnel login
fi

if "$CF" tunnel info "$NAME" >/dev/null 2>&1; then
  echo "==> Tunnel '$NAME' already exists; reusing it."
else
  echo "==> Creating tunnel '$NAME'"
  "$CF" tunnel create "$NAME"
fi

echo "==> Pointing $HOST at it"
"$CF" tunnel route dns --overwrite-dns "$NAME" "$HOST"

cat > "$ROOT/.aniverse_tunnel" <<EOF
# Written by scripts/setup_named_tunnel.sh; read by start_all.sh. Delete it to go
# back to quick tunnels with random addresses.
export ANIVERSE_TUNNEL_NAME="$NAME"
export ANIVERSE_PUBLIC_URL="https://$HOST"
EOF

echo
echo "Done. From now on ./start_all.sh serves AniVerse at https://$HOST"
echo "In the app, set the server once under the gear icon to https://$HOST"
