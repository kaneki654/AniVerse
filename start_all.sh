#!/usr/bin/env bash
# AniVerse — start everything.
#
#   ./start_all.sh                 servers + tunnel, and publish the tunnel URL
#   ./start_all.sh --no-publish    servers + tunnel, print the URL instead
#   ./start_all.sh --no-tunnel     servers only (this is what run.sh does)
#
# Publishing matters: every cloudflared start gets a fresh random URL, and the
# Android app looks the current one up from the install site. Starting a tunnel
# without publishing it leaves the app pointed at the previous, now-dead address
# — which looks exactly like the app being broken.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

WITH_TUNNEL=1
WITH_PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --no-tunnel)  WITH_TUNNEL=0 ;;
    --no-publish) WITH_PUBLISH=0 ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi
fi

# --- dependency preflight -----------------------------------------------------
# Without this a missing package just makes uvicorn exit on import, the restart
# loop respawns it every 3s, and all you see is a health check timing out. The
# usual cause is installing only the root requirements.txt, which does not carry
# the backend's packages -- Crypto (pycryptodome) is the one that bites first.
check_deps() {
  local missing
  missing="$("$PY" - <<'PYCHECK' 2>/dev/null
import importlib.util as u
need = [("fastapi","fastapi"), ("uvicorn","uvicorn"), ("httpx","httpx"),
        ("jinja2","jinja2"), ("Crypto","pycryptodome"), ("numpy","numpy"),
        ("rapidfuzz","rapidfuzz"), ("selectolax","selectolax"), ("m3u8","m3u8"),
        ("apscheduler","APScheduler"), ("py_mini_racer","mini-racer")]
print(" ".join(pkg for mod, pkg in need if u.find_spec(mod) is None))
PYCHECK
)"
  [ -z "$missing" ] && return 0
  echo
  echo "Missing Python packages: $missing"
  echo
  echo "Install both requirements files with the same interpreter this script"
  echo "uses ($PY) -- the root one alone does not cover the backend:"
  echo
  echo "  $PY -m pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt"
  echo
  exit 1
}

say() { printf '\n\033[1;31m==>\033[0m %s\n' "$*"; }

# --- free the ports ----------------------------------------------------------
# A leftover server keeps answering while the new one dies on a bind failure and
# its restart loop spins, which reads exactly like a code change doing nothing.
free_port() {
  local port="$1" pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -i:"$port" -sTCP:LISTEN 2>/dev/null || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "$port" 2>/dev/null | tr -d ':' || true)"
  elif command -v ss >/dev/null 2>&1; then
    pids="$(ss -lptnH "sport = :$port" 2>/dev/null |
            grep -oE 'pid=[0-9]+' | cut -d= -f2 || true)"
  fi
  [ -n "$pids" ] || return 0
  echo "  stopping process(es) on $port: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 1
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
}

run_forever() {
  local name="$1"; shift
  local workdir="$1"; shift
  local log="$LOG_DIR/$name.log"
  (
    cd "$workdir" || exit 1
    while true; do
      echo "[$(date -Is)] starting $name" >> "$log"
      "$@" >> "$log" 2>&1
      echo "[$(date -Is)] $name exited $? - restarting in 3s" >> "$log"
      sleep 3
    done
  ) &
  eval "${name}_PID=$!"
}

TUNNEL_PID=""
cleanup() {
  echo
  say "Stopping AniVerse"
  for pid in "${backend_PID:-}" "${frontend_PID:-}" "$TUNNEL_PID"; do
    [ -n "$pid" ] || continue
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup INT TERM

check_deps

say "Clearing ports 8000 and 8001"
free_port 8001
free_port 8000
sleep 1

# --- servers -----------------------------------------------------------------
say "Starting backend on 8001"
run_forever backend "$ROOT/AniVerseApiUrl" \
  "$PY" -m uvicorn app.main:app --host 0.0.0.0 --port 8001

for _ in $(seq 1 30); do
  curl -fsS http://localhost:8001/health >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -fsS http://localhost:8001/health >/dev/null 2>&1; then
  echo "  backend did not come up — see $LOG_DIR/backend.log" >&2
  cleanup
fi
echo "  backend ok"

say "Starting frontend on 8000"
run_forever frontend "$ROOT" \
  "$PY" -m uvicorn app.main:app --host 0.0.0.0 --port 8000

for _ in $(seq 1 30); do
  curl -fsS http://localhost:8000/ >/dev/null 2>&1 && break
  sleep 1
done
if ! curl -fsS http://localhost:8000/ >/dev/null 2>&1; then
  echo "  frontend did not come up — see $LOG_DIR/frontend.log" >&2
  cleanup
fi
echo "  frontend ok"

if [ "$WITH_TUNNEL" -eq 0 ]; then
  say "Running (no tunnel)"
  echo "  Backend  : http://localhost:8001"
  echo "  Frontend : http://localhost:8000"
  echo "  Logs     : $LOG_DIR"
  echo
  echo "Press Ctrl+C to stop."
  wait
  exit 0
fi

# --- tunnel ------------------------------------------------------------------
# Search order: an explicit CLOUDFLARED override, then PATH (under both names,
# since git-bash needs the .exe), then the usual install locations for Linux,
# macOS and Windows. The Windows paths matter because this script also runs
# under git-bash, where the old Linux-only list reported "not found" and
# silently skipped the tunnel on a machine that had cloudflared at C:\Tools.
find_cloudflared() {
  local c
  if [ -n "${CLOUDFLARED:-}" ]; then
    [ -x "${CLOUDFLARED}" ] && { printf '%s' "${CLOUDFLARED}"; return 0; }
    echo "CLOUDFLARED is set to '${CLOUDFLARED}' but that is not executable" >&2
    return 1
  fi
  for c in cloudflared cloudflared.exe; do
    if command -v "$c" >/dev/null 2>&1; then
      printf '%s' "$(command -v "$c")"; return 0
    fi
  done
  for c in     /usr/local/bin/cloudflared     /usr/bin/cloudflared     /opt/cloudflared/cloudflared     /snap/bin/cloudflared     /opt/homebrew/bin/cloudflared     "${HOME:-}/.local/bin/cloudflared"     "${HOME:-}/bin/cloudflared"     /c/Tools/cloudflared.exe     "/c/Program Files/cloudflared/cloudflared.exe"     "/c/Program Files (x86)/cloudflared/cloudflared.exe"
  do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

CF="$(find_cloudflared || true)"

if [ -z "$CF" ]; then
  echo
  echo "cloudflared not found — servers are up, but nothing is exposed publicly."
  echo "Install it, then re-run:"
  echo "  Debian/Ubuntu  sudo apt install cloudflared"
  echo "  macOS          brew install cloudflared"
  echo "  Manual         https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
  echo
  echo "Frontend is still on http://localhost:8000 — Ctrl+C to stop."
  wait
  exit 0
fi

say "Starting tunnel"
TUNNEL_LOG="$LOG_DIR/tunnel.log"
: > "$TUNNEL_LOG"
"$CF" tunnel --url http://localhost:8000 >> "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

URL=""
for _ in $(seq 1 40); do
  URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1)"
  [ -n "$URL" ] && break
  sleep 2
done

if [ -z "$URL" ]; then
  echo "  no tunnel URL appeared — see $TUNNEL_LOG" >&2
  echo "  servers are still running on localhost."
  wait
  exit 1
fi
echo "  $URL"

# Cloudflare needs a moment to publish DNS for a fresh quick tunnel.
echo -n "  waiting for it to answer"
TUNNEL_OK=0
for _ in $(seq 1 20); do
  if curl -fsS -o /dev/null --max-time 15 "$URL/" 2>/dev/null; then
    TUNNEL_OK=1; break
  fi
  echo -n "."
  sleep 5
done
echo
[ "$TUNNEL_OK" -eq 1 ] && echo "  tunnel ok" || \
  echo "  tunnel not answering yet — it often still works; check $TUNNEL_LOG"

# --- publish the address -----------------------------------------------------
# Without this the app keeps using whatever address was published last, which is
# now dead — the single most common reason "the app stopped working".
if [ "$WITH_PUBLISH" -eq 1 ]; then
  say "Publishing the address so the app can find it"
  if "$PY" "$ROOT/aniverse_site/build_site.py" --host "$URL"; then
    if command -v vercel >/dev/null 2>&1; then
      if (cd "$ROOT/aniverse_site" && vercel deploy --prod --yes >/dev/null 2>&1); then
        echo "  published to https://aniversesite.vercel.app"
      else
        echo "  vercel deploy failed — publish manually:"
        echo "    cd aniverse_site && vercel deploy --prod"
      fi
    else
      echo "  vercel CLI not installed, so the app was NOT told about this URL."
      echo "  Either install it (npm i -g vercel) and re-run, or from a machine"
      echo "  that has it:"
      echo "    python3 aniverse_site/build_site.py --host $URL"
      echo "    cd aniverse_site && vercel deploy --prod"
    fi
  else
    echo "  build_site.py failed; the app was not told about this URL." >&2
  fi
fi

say "AniVerse is running"
echo "  Frontend : http://localhost:8000"
echo "  Backend  : http://localhost:8001"
echo "  Public   : $URL"
echo "  Logs     : $LOG_DIR"
echo
echo "On the phone: the app finds this address by itself from build 8 onward."
echo "On an older build, paste the Public URL under the gear icon."
echo
echo "Press Ctrl+C to stop everything."
wait
