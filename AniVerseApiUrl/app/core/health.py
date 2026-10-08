"""
Recent provider and resolve outcomes, kept in memory for the status page.

Each provider attempt is one event (ok / empty / error / timeout), and each
episode lookup one resolve (playable or not). The last day of both is saved to
data/health.json every few minutes and on shutdown, and read back on start, so
a restart does not wipe the status page.
(resilience.py's ProviderHealthManager keeps only a running score and is not
wired in anywhere; this keeps the history a status page needs.)
"""

import json
import os
import time
from collections import deque
from pathlib import Path
from typing import Any

_attempts: deque = deque(maxlen=6000)   # (ts, provider, outcome, seconds, error)
_resolves: deque = deque(maxlen=3000)   # (ts, ok, anilist_id, episode, category, error, seconds)


STORE = Path(__file__).resolve().parents[2] / "data" / "health.json"


def save(path: Path = STORE) -> None:
    """Write the last day of events, atomically."""
    cutoff = time.time() - 86400
    body = {
        "attempts": [list(a) for a in _attempts if a[0] > cutoff],
        "resolves": [list(r) for r in _resolves if r[0] > cutoff],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(body))
    os.replace(tmp, path)


def load(path: Path = STORE) -> None:
    """Read back what save() wrote; anything unreadable is simply skipped."""
    try:
        body = json.loads(path.read_text())
    except (OSError, ValueError):
        return
    cutoff = time.time() - 86400
    for a in body.get("attempts", []):
        if isinstance(a, list) and len(a) == 5 and a[0] > cutoff:
            _attempts.append(tuple(a))
    for r in body.get("resolves", []):
        if isinstance(r, list) and len(r) == 7 and r[0] > cutoff:
            _resolves.append(tuple(r))


def record_attempt(provider: str, outcome: str, seconds: float, error: str = "") -> None:
    _attempts.append((time.time(), provider, outcome, round(seconds, 2), (error or "")[:200]))


def record_resolve(ok: bool, anilist_id: str, episode: int, category: str, error: str, seconds: float) -> None:
    _resolves.append((time.time(), ok, anilist_id, episode, category, (error or "")[:200], round(seconds, 2)))


def summary() -> dict[str, Any]:
    now = time.time()
    providers: dict[str, dict[str, Any]] = {}
    ok_seconds: dict[str, list[float]] = {}
    for ts, name, outcome, secs, err in _attempts:
        if now - ts > 86400:
            continue
        p = providers.setdefault(name, {"name": name, "hour": {}, "day": {}, "lastError": None, "lastOk": None})
        for window, span in (("hour", 3600), ("day", 86400)):
            if now - ts <= span:
                p[window][outcome] = p[window].get(outcome, 0) + 1
        if outcome == "ok":
            ok_seconds.setdefault(name, []).append(secs)
            p["lastOk"] = int(ts)
        elif err:
            p["lastError"] = {"at": int(ts), "error": err}
    out_providers = []
    for name, p in providers.items():
        total = sum(p["day"].values())
        oks = ok_seconds.get(name, [])
        out_providers.append({
            **p,
            "attempts": total,
            "successRate": round(100 * p["day"].get("ok", 0) / total) if total else None,
            "avgSeconds": round(sum(oks) / len(oks), 1) if oks else None,
        })
    out_providers.sort(key=lambda p: -(p["successRate"] if p["successRate"] is not None else -1))

    # Playable share per hour over the last day, oldest first.
    hours = []
    for h in range(23, -1, -1):
        lo, hi = now - (h + 1) * 3600, now - h * 3600
        bucket = [r for r in _resolves if lo < r[0] <= hi]
        hours.append({"start": int(lo), "total": len(bucket), "playable": sum(1 for r in bucket if r[1])})
    day = [r for r in _resolves if now - r[0] <= 86400]
    playable = [r for r in day if r[1]]
    failures = [
        {"at": int(r[0]), "anilistId": r[2], "episode": r[3], "category": r[4], "error": r[5]}
        for r in reversed(_resolves) if not r[1]
    ][:20]
    return {
        "now": int(now),
        "providers": out_providers,
        "coverage": {
            "total": len(day),
            "playable": len(playable),
            "avgSeconds": round(sum(r[6] for r in playable) / len(playable), 1) if playable else None,
        },
        "hours": hours,
        "recentFailures": failures,
    }


load()
