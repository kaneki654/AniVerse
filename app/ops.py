"""
The server keeping an eye on itself, for the status page:

- free disk space. A runaway log once filled the disk and every save failed
  silently; now low space is logged, shown on /status, and a save that fails
  for lack of space says so (HTTP 507) instead of a bare 500;
- the daily stream sweep (scripts/sweep_playable.py --trending) and how much
  of what is popular right now actually plays;
- errors the app and the website send in (crashes and episodes that would not
  play), kept in logs/client_errors.log without IP addresses.
"""

import asyncio
import errno
import json
import shutil
import sqlite3
import threading
import time
import traceback
from pathlib import Path

from fastapi import APIRouter, FastAPI, Request, Response
from fastapi.responses import JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field

from app import accounts

ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT / "logs"
ERRORS_LOG = LOG_DIR / "client_errors.log"
SWEEP_FILE = ROOT / "data" / "sweep.json"

LOW_FRACTION = 0.10
ERRORS_PER_HOUR = 30
DISK_FULL = ("The server's disk is full, so nothing can be saved right now. "
             "It works again as soon as space is freed.")

router = APIRouter(prefix="/api")


# --- disk ----------------------------------------------------------------------------

def disk() -> dict:
    u = shutil.disk_usage(ROOT)
    # free here is what an ordinary user can still write, which is what counts.
    fraction = u.free / u.total if u.total else 0.0
    return {
        "freeGb": round(u.free / 1e9, 1),
        "totalGb": round(u.total / 1e9, 1),
        "freePercent": round(100 * fraction, 1),
        "low": fraction < LOW_FRACTION,
    }


async def watch_disk(every: float = 300):
    """Logs a warning (at most hourly) while free space is under 10%."""
    warned = 0.0
    while True:
        try:
            d = disk()
            if d["low"] and time.time() - warned > 3600:
                warned = time.time()
                print(f"WARNING: disk nearly full: {d['freeGb']} GB free ({d['freePercent']}%). "
                      "Saves will start failing when it reaches zero.", flush=True)
        except OSError:
            pass
        await asyncio.sleep(every)


def is_disk_full(exc: BaseException) -> bool:
    if isinstance(exc, OSError) and exc.errno == errno.ENOSPC:
        return True
    return isinstance(exc, sqlite3.OperationalError) and "disk is full" in str(exc)


def install(app: FastAPI) -> None:
    """A save that fails for lack of space answers 507 with a message people can read."""

    async def handler(_request: Request, exc: Exception):
        if is_disk_full(exc):
            print(f"Save failed, disk full: {exc}", flush=True)
            return JSONResponse({"detail": DISK_FULL}, status_code=507)
        traceback.print_exception(exc)
        return PlainTextResponse("Internal Server Error", status_code=500)

    app.add_exception_handler(sqlite3.OperationalError, handler)
    app.add_exception_handler(OSError, handler)


# --- the daily sweep -----------------------------------------------------------------

def sweep() -> dict | None:
    try:
        data = json.loads(SWEEP_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    total = int(data.get("total") or 0)
    ok = int(data.get("ok") or 0)
    return {
        "at": data.get("at"),
        "total": total,
        "ok": ok,
        "percent": round(100 * ok / total) if total else None,
        "servers": data.get("servers") or {},
        "failing": (data.get("failing") or [])[:12],
    }


# --- error reports from the app and the website ----------------------------------------

class ClientError(BaseModel):
    source: str = Field(max_length=16)               # "app" or "web"
    version: str = Field("", max_length=32)
    kind: str = Field("error", max_length=32)        # error, crash, playback
    message: str = Field(max_length=2000)
    stack: str = Field("", max_length=8000)
    where: str = Field("", max_length=200)           # the screen or page


_lock = threading.Lock()
_hits: dict[str, list[float]] = {}


def _over_limit(ip: str) -> bool:
    now = time.time()
    with _lock:
        hits = [t for t in _hits.get(ip, []) if now - t < 3600]
        over = len(hits) >= ERRORS_PER_HOUR
        if not over:
            hits.append(now)
        _hits[ip] = hits
        return over


@router.post("/client-errors", status_code=204)
def client_error(body: ClientError, request: Request):
    # Past the limit the report is dropped quietly: a client stuck in a crash
    # loop must not fill the disk, and must not retry either.
    if not _over_limit(accounts._client_ip(request)):
        line = {
            "at": int(time.time()),
            **body.model_dump(),
            "ua": request.headers.get("user-agent", "")[:200],
        }
        try:
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            with open(ERRORS_LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps(line, ensure_ascii=False) + "\n")
        except OSError:
            pass  # an error report must never become an error itself
    return Response(status_code=204)


def recent_errors(window: int = 86400, limit: int = 8) -> dict:
    """How many reports came in over the last day, and the latest few (no stacks)."""
    rows = []
    try:
        with open(ERRORS_LOG, "rb") as f:
            f.seek(0, 2)
            start = max(0, f.tell() - 512 * 1024)
            f.seek(start)
            tail = f.read().decode("utf-8", "replace").splitlines()
            if start:
                tail = tail[1:]  # cut part way through a line
    except OSError:
        tail = []
    cutoff = time.time() - window
    for raw in tail:
        try:
            row = json.loads(raw)
        except ValueError:
            continue
        if isinstance(row, dict) and row.get("at", 0) >= cutoff:
            rows.append(row)
    latest = [
        {k: (str(r.get(k, ""))[:160] if k != "at" else r.get("at")) for k in ("at", "source", "version", "kind", "where", "message")}
        for r in rows[-limit:]
    ]
    return {"last24h": len(rows), "latest": latest[::-1]}


@router.get("/ops")
def ops():
    return {"now": int(time.time()), "disk": disk(), "sweep": sweep(), "clientErrors": recent_errors()}
