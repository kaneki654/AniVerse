#!/usr/bin/env bash
# AniVerse launcher — starts backend (8001) and frontend (8000), restarts either on crash.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
export PYTHONPATH="$ROOT/libs"

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

run_forever() {
  local name="$1"; shift
  local workdir="$1"; shift
  local log="$LOG_DIR/$name.log"
  (
    cd "$workdir"
    while true; do
      echo "[$(date -Is)] starting $name" >> "$log"
      echo "[$(date -Is)] starting $name with: $*" >&2
      "$@" >> "$log" 2>&1
      echo "[$(date -Is)] $name exited $? — restarting in 3s" >> "$log"
      sleep 3
    done
  ) &
  eval "${name}_PID=$!"
}

run_forever backend "$ROOT/AniVerseApiUrl" \
  python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8001

# Wait for backend /health (up to 20s) before starting frontend.
for i in $(seq 1 20); do
  curl -fsS http://localhost:8001/health >/dev/null 2>&1 && break
  sleep 1
done

run_forever frontend "$ROOT" \
  python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000

trap 'kill $backend_PID $frontend_PID 2>/dev/null; exit 0' INT TERM
wait
