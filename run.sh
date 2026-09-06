#!/usr/bin/env bash
# AniVerse launcher (Linux/macOS) — servers only, the mirror of run.bat.
#
# Delegates to start_all.sh so the port-clearing, restart loops and health gates
# live in one place. For the tunnel and address publishing as well, run
# start_all.sh directly.
exec "$(cd "$(dirname "$0")" && pwd)/start_all.sh" --no-tunnel "$@"
