"""
Which hosts /proxy/* will fetch from.

The proxy exists to add the Referer the stream CDNs demand. Left open it
fetches any address for anyone -- and since it answers cross-origin requests
(a Chromecast needs that), any website's scripts could read through it too.

So it only fetches from hosts this server itself handed out: the stream and
subtitle hosts in /api/source answers, and the segment, key and playlist hosts
inside the playlists it rewrote. Stream providers rotate their domains, so a
fixed list would break playback; learning them as they are handed out keeps up
on its own. A host is remembered for TTL after it was last handed out, in the
accounts database, so a restart in the middle of an episode does not cut it off.

Addresses on this machine or the local network are refused outright.
"""

import ipaddress
import sqlite3
import threading
import time
from urllib.parse import urlparse

from app import accounts

TTL = 14 * 86400
# A host handed out again within this long is not written to the database again.
_REFRESH = 3600

_SCHEMA = "CREATE TABLE IF NOT EXISTS proxy_hosts (host TEXT PRIMARY KEY, seen INTEGER NOT NULL)"

_lock = threading.Lock()
_seen: dict[str, float] = {}
_ready = False


def _db() -> sqlite3.Connection:
    accounts.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(accounts.DB_PATH, timeout=10)
    conn.execute(_SCHEMA)
    return conn


def _load():
    global _ready
    if _ready:
        return
    cutoff = time.time() - TTL
    try:
        with _db() as conn:
            for host, seen in conn.execute("SELECT host, seen FROM proxy_hosts WHERE seen > ?", (cutoff,)):
                _seen[host] = max(_seen.get(host, 0), seen)
    except sqlite3.Error:
        pass  # the in-memory list still works; it just starts empty
    _ready = True


def host_of(url: str) -> str | None:
    try:
        u = urlparse(url)
    except ValueError:
        return None
    if u.scheme not in ("http", "https") or not u.hostname:
        return None
    return u.hostname.lower().rstrip(".")


def _local(host: str) -> bool:
    if host == "localhost" or host.endswith((".localhost", ".local", ".internal")):
        return True
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False  # a name: only names the server handed out get through anyway
    return not ip.is_global


def allow(url: str) -> None:
    """Remember the host of a URL this server is handing out through the proxy."""
    host = host_of(url)
    if not host or _local(host):
        return
    now = time.time()
    with _lock:
        _load()
        if now - _seen.get(host, 0) < _REFRESH:
            return
        _seen[host] = now
    try:
        with _db() as conn:
            conn.execute(
                "INSERT INTO proxy_hosts (host, seen) VALUES (?, ?)"
                " ON CONFLICT(host) DO UPDATE SET seen = excluded.seen",
                (host, int(now)),
            )
    except sqlite3.Error:
        pass  # remembered in memory; a full disk must not stop playback


def allowed(url: str) -> bool:
    """Whether the proxy may fetch this URL."""
    host = host_of(url)
    if not host or _local(host):
        return False
    with _lock:
        _load()
        return time.time() - _seen.get(host, 0) < TTL


def forget_all() -> None:
    """For tests: start from nothing."""
    global _ready
    with _lock:
        _seen.clear()
        _ready = False
