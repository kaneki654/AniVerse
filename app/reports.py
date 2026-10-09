"""
Viewers telling the server a stream plays wrong (frozen, wrong episode, no
sound, constant buffering).

A reported stream is left out of /api/source answers for that episode for a
few hours -- long enough for the provider to fix it or the cache to move on,
short enough that a mistaken report heals. Two rules keep one person from
hiding streams from everybody:

- it is hidden for everyone only once two different people report it; the
  person who reported it stops getting it straight away;
- each person can make a limited number of reports an hour.

People are told apart by a salted hash of their IP address, never the
address itself. Reports are kept in the accounts database, so a restart does
not forget them.
"""

import hashlib
import secrets
import sqlite3
import time

from app import accounts

TTL = 6 * 3600
PER_HOUR = 12
QUORUM = 2

_SCHEMA = """
CREATE TABLE IF NOT EXISTS stream_reports (
    anime     TEXT NOT NULL,
    ep        TEXT NOT NULL,
    category  TEXT NOT NULL,
    url       TEXT NOT NULL,
    reporter  TEXT NOT NULL,
    at        INTEGER NOT NULL,
    reason    TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (anime, ep, category, url, reporter)
);
CREATE INDEX IF NOT EXISTS stream_reports_by_reporter ON stream_reports (reporter, at);
"""

_salt: str | None = None


def _conn() -> sqlite3.Connection:
    accounts.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(accounts.DB_PATH, timeout=10)
    conn.executescript(_SCHEMA)
    return conn


def reporter_id(ip: str) -> str:
    """A stable, salted stand-in for an IP address."""
    global _salt
    if _salt is None:
        path = accounts.DATA_DIR / "report_salt"
        try:
            _salt = path.read_text().strip()
        except OSError:
            _salt = secrets.token_hex(16)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(_salt)
            path.chmod(0o600)
    return hashlib.sha256(f"{_salt}:{ip}".encode()).hexdigest()[:16]


class RateLimited(Exception):
    pass


def record(anime: str, ep: str, category: str, url: str, ip: str, reason: str = "") -> None:
    """Note a report. Raises RateLimited past PER_HOUR reports from one person."""
    who = reporter_id(ip)
    now = int(time.time())
    with _conn() as conn:
        recent = conn.execute(
            "SELECT COUNT(*) FROM stream_reports WHERE reporter = ? AND at > ?", (who, now - 3600)
        ).fetchone()[0]
        if recent >= PER_HOUR:
            raise RateLimited()
        conn.execute(
            "INSERT INTO stream_reports (anime, ep, category, url, reporter, at, reason) VALUES (?, ?, ?, ?, ?, ?, ?)"
            " ON CONFLICT(anime, ep, category, url, reporter) DO UPDATE SET at = excluded.at, reason = excluded.reason",
            (anime, str(ep), category, url, who, now, reason[:120]),
        )
        conn.execute("DELETE FROM stream_reports WHERE at < ?", (now - TTL,))


def hidden(anime: str, ep: str, category: str, ip: str | None = None) -> set[str]:
    """Upstream URLs to leave out for this episode: reported by enough people,
    or by the person asking."""
    who = reporter_id(ip) if ip else None
    since = int(time.time()) - TTL
    with _conn() as conn:
        rows = conn.execute(
            "SELECT url, COUNT(DISTINCT reporter), SUM(reporter = ?) FROM stream_reports"
            " WHERE anime = ? AND ep = ? AND category = ? AND at > ? GROUP BY url",
            (who or "", anime, str(ep), category, since),
        ).fetchall()
    return {url for url, people, mine in rows if people >= QUORUM or (mine or 0) > 0}
