#!/usr/bin/env bash
# AniVerse launcher (Linux/macOS) — mirrors run.bat.
#
# Starts the backend (8001) and the frontend (8000), restarts either if it
# crashes, and clears both ports first so a leftover server cannot keep serving
# old code while the new one fails to bind.
#
# Dependencies come from pip, not from libs/. That folder only ever held the
# frontend's packages and is missing every backend one (numpy, rapidfuzz,
# selectolax, pycryptodome, mini-racer, m3u8, APScheduler), so putting it on
# PYTHONPATH breaks the backend outright. Install both requirements files:
#   pip install -r AniVerseApiUrl/requirements.txt -r requirements.txt
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi
fi

# --- Stop anything already holding our ports ---------------------------------
# Without this the new server exits on a bind failure, the restart loop spins,
# and the OLD process carries on answering requests -- which looks exactly like
# the code changes having no effect.
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
  echo "Stopping process(es) on port $port: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 1
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
}

echo "Stopping any previous AniVerse servers..."
free_port 8001
free_port 8000
sleep 1

# --- Restart loops -----------------------------------------------------------
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

echo "Starting backend on 8001..."
run_forever backend "$ROOT/AniVerseApiUrl" \
  "$PY" -m uvicorn app.main:app --host 0.0.0.0 --port 8001

# Wait for the backend to answer before starting the frontend, so the first
# page load does not race an unready API.
for _ in $(seq 1 20); do
  curl -fsS http://localhost:8001/health >/dev/null 2>&1 && break
  sleep 1
done

echo "Starting frontend on 8000..."
run_forever frontend "$ROOT" \
  "$PY" -m uvicorn app.main:app --host 0.0.0.0 --port 8000

cleanup() {
  echo
  echo "Stopping AniVerse..."
  kill "${backend_PID:-}" "${frontend_PID:-}" 2>/dev/null || true
  # The loops run in subshells; take their children down too.
  pkill -P "${backend_PID:-0}" 2>/dev/null || true
  pkill -P "${frontend_PID:-0}" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

echo
echo "AniVerse is running. Press Ctrl+C to stop."
echo "Backend  : http://localhost:8001"
echo "Frontend : http://localhost:8000"
echo "Logs     : $LOG_DIR"
wait
