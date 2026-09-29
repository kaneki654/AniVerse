"""Accounts and watch history for the AniVerse app.

Two ways in: a username and password, or a Google account. Either way the app
gets back an opaque session token and sends it as `Authorization: Bearer ...`.
Watch history is kept per account so it follows the user between devices; the
app also keeps its own copy, so history works signed out and survives the
server being unreachable.

Storage is a single SQLite file under data/ (gitignored: it holds password
hashes and session tokens). Nothing here needs a package beyond what the web
app already has -- passwords use the standard library's scrypt, and Google ID
tokens are checked against Google's tokeninfo endpoint.

Google sign-in is off until a Web OAuth client ID is configured, via the
ANIVERSE_GOOGLE_CLIENT_ID environment variable or data/google_client_id.txt.
The app asks /api/auth/config for it at runtime, so turning Google on never
needs a new APK.
"""

import base64
import hashlib
import hmac
import os
import pathlib
import re
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from typing import List, Optional

import httpx
from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel

DATA_DIR = pathlib.Path(__file__).resolve().parent.parent / "data"
DB_PATH = pathlib.Path(os.environ.get("ANIVERSE_DB") or DATA_DIR / "aniverse.db")
GOOGLE_CLIENT_ID_FILE = DATA_DIR / "google_client_id.txt"

SESSION_TTL = 90 * 24 * 3600
# Writing last_used on every request would turn each history sync into a
# write; an hour is plenty of resolution for a sliding expiry.
SESSION_TOUCH_INTERVAL = 3600

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,24}$")
PASSWORD_MIN, PASSWORD_MAX = 8, 128

# scrypt at n=2^14, r=8 costs ~16 MB and a few tens of ms per hash: cheap for a
# login, expensive for anyone replaying a stolen database.
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2 ** 14, 8, 1

HISTORY_BATCH_MAX = 200
HISTORY_RETURN_MAX = 500

router = APIRouter(prefix="/api")


# --- storage -----------------------------------------------------------------

_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT UNIQUE COLLATE NOCASE,
    password_hash TEXT,
    google_sub    TEXT UNIQUE,
    email         TEXT,
    display_name  TEXT NOT NULL,
    avatar_url    TEXT,
    created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash   TEXT PRIMARY KEY,
    user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS history (
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    anime_id    TEXT NOT NULL,
    episode     INTEGER NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    cover       TEXT NOT NULL DEFAULT '',
    position_ms INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    updated_at  INTEGER NOT NULL,
    deleted     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, anime_id, episode)
);
CREATE INDEX IF NOT EXISTS history_by_time ON history(user_id, updated_at DESC);
"""

_init_lock = threading.Lock()
_initialised = False


@contextmanager
def _db():
    """A connection per call: sqlite3 connections must not cross threads, and
    FastAPI runs these sync handlers on a thread pool."""
    global _initialised
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        if not _initialised:
            with _init_lock:
                if not _initialised:
                    conn.execute("PRAGMA journal_mode = WAL")
                    conn.executescript(_SCHEMA)
                    _initialised = True
        yield conn
        conn.commit()
    finally:
        conn.close()


# --- passwords and tokens ------------------------------------------------------

def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt,
                            n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P, dklen=32)
    b64 = lambda b: base64.b64encode(b).decode("ascii")
    return f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}${b64(salt)}${b64(digest)}"


def _check_password(password: str, stored: Optional[str]) -> bool:
    try:
        scheme, n, r, p, salt, digest = (stored or "").split("$")
        if scheme != "scrypt":
            return False
        expected = base64.b64decode(digest)
        actual = hashlib.scrypt(password.encode("utf-8"), salt=base64.b64decode(salt),
                                n=int(n), r=int(r), p=int(p), dklen=len(expected))
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


# Checked against when the username does not exist, so a missing account costs
# the same scrypt as a wrong password and response time does not reveal which
# usernames are taken.
_DUMMY_HASH = _hash_password(secrets.token_urlsafe(16))


def _token_hash(token: str) -> str:
    # Only the hash is stored: a leaked database cannot be replayed as sessions.
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _new_session(conn: sqlite3.Connection, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    now = int(time.time())
    conn.execute(
        "INSERT INTO sessions (token_hash, user_id, created_at, last_used_at, expires_at)"
        " VALUES (?, ?, ?, ?, ?)",
        (_token_hash(token), user_id, now, now, now + SESSION_TTL),
    )
    # Expired sessions are swept whenever a new one is made, which is often
    # enough that the table never needs a scheduled job.
    conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))
    return token


def _user_json(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "username": row["username"],
        "display_name": row["display_name"],
        "email": row["email"],
        "avatar_url": row["avatar_url"],
        "provider": "google" if row["google_sub"] else "password",
    }


def _session_user(conn: sqlite3.Connection, authorization: Optional[str]) -> sqlite3.Row:
    """The signed-in user for an `Authorization: Bearer` header, or 401."""
    token = ""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Not signed in")

    now = int(time.time())
    th = _token_hash(token)
    row = conn.execute(
        "SELECT u.*, s.last_used_at AS s_last_used FROM sessions s"
        " JOIN users u ON u.id = s.user_id"
        " WHERE s.token_hash = ? AND s.expires_at > ?",
        (th, now),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="Session expired, sign in again")

    if now - row["s_last_used"] > SESSION_TOUCH_INTERVAL:
        conn.execute(
            "UPDATE sessions SET last_used_at = ?, expires_at = ? WHERE token_hash = ?",
            (now, now + SESSION_TTL, th),
        )
    return row


# --- brute-force limits ---------------------------------------------------------

# The server is reachable by anyone who has the tunnel address, so repeated
# password guesses are throttled. Kept in memory: a restart clears it, which
# is fine for slowing down guessing, which is all this is for.
_attempts_lock = threading.Lock()
_failed_logins: dict = {}
_registrations: dict = {}
LOGIN_WINDOW, LOGIN_MAX_FAILURES = 15 * 60, 8
REGISTER_WINDOW, REGISTER_MAX = 3600, 10


def _client_ip(request: Request) -> str:
    # cloudflared connects from localhost, so the socket address is the same for
    # every user; Cloudflare puts the real one in this header.
    return (request.headers.get("cf-connecting-ip")
            or request.headers.get("x-forwarded-for", "").split(",")[0].strip()
            or (request.client.host if request.client else "unknown"))


def _recent(bucket: dict, key, window: int) -> list:
    now = time.time()
    hits = [t for t in bucket.get(key, []) if now - t < window]
    bucket[key] = hits
    return hits


def _check_login_allowed(ip: str, username: str):
    with _attempts_lock:
        if (len(_recent(_failed_logins, ("ip", ip), LOGIN_WINDOW)) >= LOGIN_MAX_FAILURES * 3
                or len(_recent(_failed_logins, ("user", username.lower()), LOGIN_WINDOW))
                >= LOGIN_MAX_FAILURES):
            raise HTTPException(status_code=429,
                                detail="Too many attempts. Wait 15 minutes and try again.")


def _record_login_failure(ip: str, username: str):
    with _attempts_lock:
        now = time.time()
        _recent(_failed_logins, ("ip", ip), LOGIN_WINDOW).append(now)
        _recent(_failed_logins, ("user", username.lower()), LOGIN_WINDOW).append(now)


def _check_registration_allowed(ip: str):
    with _attempts_lock:
        hits = _recent(_registrations, ip, REGISTER_WINDOW)
        if len(hits) >= REGISTER_MAX:
            raise HTTPException(status_code=429,
                                detail="Too many accounts created. Try again later.")
        hits.append(time.time())


# --- Google ------------------------------------------------------------------------

def google_client_id() -> Optional[str]:
    """The Web OAuth client ID the app must request ID tokens for, if configured."""
    value = os.environ.get("ANIVERSE_GOOGLE_CLIENT_ID", "").strip()
    if not value:
        try:
            value = GOOGLE_CLIENT_ID_FILE.read_text(encoding="utf-8").strip()
        except OSError:
            value = ""
    return value or None


def _verify_google_token(id_token: str, client_id: str) -> dict:
    """Claims of a Google ID token, after checking it was issued to us."""
    try:
        resp = httpx.get("https://oauth2.googleapis.com/tokeninfo",
                         params={"id_token": id_token}, timeout=10)
    except httpx.HTTPError:
        raise HTTPException(status_code=503, detail="Could not reach Google, try again")
    if resp.status_code != 200:
        raise HTTPException(status_code=401, detail="Google sign-in was rejected")

    claims = resp.json()
    # tokeninfo only proves Google signed it; audience and issuer prove it was
    # issued for this app rather than replayed from some other one.
    if claims.get("aud") != client_id:
        raise HTTPException(status_code=401, detail="Google token is for a different app")
    if claims.get("iss") not in ("accounts.google.com", "https://accounts.google.com"):
        raise HTTPException(status_code=401, detail="Google token has the wrong issuer")
    try:
        if int(claims.get("exp", 0)) < time.time():
            raise HTTPException(status_code=401, detail="Google sign-in expired, try again")
    except (TypeError, ValueError):
        raise HTTPException(status_code=401, detail="Google sign-in was rejected")
    if not claims.get("sub"):
        raise HTTPException(status_code=401, detail="Google sign-in was rejected")
    return claims


# --- request bodies ------------------------------------------------------------------

class Credentials(BaseModel):
    username: str
    password: str
    display_name: Optional[str] = None


class GoogleLogin(BaseModel):
    id_token: str


class HistoryEntry(BaseModel):
    anime_id: str
    episode: int
    title: str = ""
    cover: str = ""
    position_ms: int = 0
    duration_ms: int = 0
    updated_at: int
    deleted: bool = False


class HistoryBatch(BaseModel):
    entries: List[HistoryEntry]


# --- auth endpoints --------------------------------------------------------------------

@router.get("/auth/config")
def auth_config():
    client_id = google_client_id()
    return {
        "password": True,
        "google": {"enabled": bool(client_id), "server_client_id": client_id},
    }


@router.post("/auth/register")
def register(body: Credentials, request: Request):
    username = body.username.strip()
    if not USERNAME_RE.match(username):
        raise HTTPException(status_code=400,
                            detail="Username must be 3-24 letters, numbers, or . _ -")
    if not PASSWORD_MIN <= len(body.password) <= PASSWORD_MAX:
        raise HTTPException(status_code=400,
                            detail=f"Password must be at least {PASSWORD_MIN} characters")
    display = (body.display_name or "").strip()[:40] or username

    _check_registration_allowed(_client_ip(request))
    password_hash = _hash_password(body.password)
    with _db() as conn:
        try:
            cur = conn.execute(
                "INSERT INTO users (username, password_hash, display_name, created_at)"
                " VALUES (?, ?, ?, ?)",
                (username, password_hash, display, int(time.time())),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="That username is taken")
        user_id = cur.lastrowid
        token = _new_session(conn, user_id)
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return {"token": token, "user": _user_json(row)}


@router.post("/auth/login")
def login(body: Credentials, request: Request):
    username = body.username.strip()
    ip = _client_ip(request)
    _check_login_allowed(ip, username)
    with _db() as conn:
        row = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
        ok = _check_password(body.password, row["password_hash"] if row else _DUMMY_HASH)
        if not row or not ok:
            _record_login_failure(ip, username)
            raise HTTPException(status_code=401, detail="Wrong username or password")
        token = _new_session(conn, row["id"])
        return {"token": token, "user": _user_json(row)}


@router.post("/auth/google")
def login_google(body: GoogleLogin):
    client_id = google_client_id()
    if not client_id:
        raise HTTPException(status_code=503,
                            detail="Google sign-in is not set up on this server")
    claims = _verify_google_token(body.id_token, client_id)

    sub = claims["sub"]
    email = claims.get("email") if str(claims.get("email_verified")).lower() == "true" else None
    name = (claims.get("name") or (email or "").split("@")[0] or "AniVerse fan")[:40]
    picture = claims.get("picture")

    with _db() as conn:
        row = conn.execute("SELECT * FROM users WHERE google_sub = ?", (sub,)).fetchone()
        if row is None:
            # Deliberately not merged into a password account by email: that
            # would let whoever controls a Google address take over a local
            # account registered under the same address.
            cur = conn.execute(
                "INSERT INTO users (google_sub, email, display_name, avatar_url, created_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (sub, email, name, picture, int(time.time())),
            )
            user_id = cur.lastrowid
        else:
            user_id = row["id"]
            conn.execute(
                "UPDATE users SET email = COALESCE(?, email), avatar_url = COALESCE(?, avatar_url)"
                " WHERE id = ?",
                (email, picture, user_id),
            )
        token = _new_session(conn, user_id)
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return {"token": token, "user": _user_json(row)}


@router.get("/auth/me")
def me(authorization: Optional[str] = Header(None)):
    with _db() as conn:
        return {"user": _user_json(_session_user(conn, authorization))}


@router.post("/auth/logout")
def logout(authorization: Optional[str] = Header(None)):
    token = (authorization or "")[7:].strip() if (authorization or "").lower().startswith("bearer ") else ""
    if token:
        with _db() as conn:
            conn.execute("DELETE FROM sessions WHERE token_hash = ?", (_token_hash(token),))
    return {"ok": True}


# --- history endpoints -----------------------------------------------------------------

def _history_rows(conn: sqlite3.Connection, user_id: int) -> list:
    rows = conn.execute(
        "SELECT anime_id, episode, title, cover, position_ms, duration_ms, updated_at, deleted"
        " FROM history WHERE user_id = ? ORDER BY updated_at DESC LIMIT ?",
        (user_id, HISTORY_RETURN_MAX),
    ).fetchall()
    return [{**dict(r), "deleted": bool(r["deleted"])} for r in rows]


@router.get("/history")
def get_history(authorization: Optional[str] = Header(None)):
    with _db() as conn:
        user = _session_user(conn, authorization)
        return {"entries": _history_rows(conn, user["id"])}


@router.put("/history")
def put_history(body: HistoryBatch, authorization: Optional[str] = Header(None)):
    """Merge the app's entries in, newest `updated_at` wins, and return the result.

    Deletions travel as entries with `deleted: true` rather than as a separate
    call, so a device that was offline when something was removed learns about
    it on its next sync instead of uploading the old entry back.
    """
    if len(body.entries) > HISTORY_BATCH_MAX:
        raise HTTPException(status_code=413, detail="Too many history entries at once")

    # A phone with its clock set years ahead would otherwise win every merge
    # for good; its entries are pulled back to "now".
    ceiling = int(time.time() * 1000) + 5 * 60 * 1000
    with _db() as conn:
        user = _session_user(conn, authorization)
        for e in body.entries:
            if not e.anime_id or len(e.anime_id) > 32 or not 0 < e.episode < 100000:
                continue
            cover = e.cover if e.cover.startswith(("http://", "https://")) else ""
            conn.execute(
                "INSERT INTO history (user_id, anime_id, episode, title, cover, position_ms,"
                " duration_ms, updated_at, deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
                " ON CONFLICT(user_id, anime_id, episode) DO UPDATE SET"
                "  title = excluded.title, cover = excluded.cover,"
                "  position_ms = excluded.position_ms, duration_ms = excluded.duration_ms,"
                "  updated_at = excluded.updated_at, deleted = excluded.deleted"
                " WHERE excluded.updated_at > history.updated_at",
                (user["id"], e.anime_id, e.episode, e.title[:300], cover[:1000],
                 max(0, e.position_ms), max(0, e.duration_ms),
                 min(e.updated_at, ceiling), int(e.deleted)),
            )
        return {"entries": _history_rows(conn, user["id"])}


@router.delete("/history")
def clear_history(authorization: Optional[str] = Header(None)):
    """Mark everything deleted (not dropped) so other devices sync the clear."""
    now = int(time.time() * 1000)
    with _db() as conn:
        user = _session_user(conn, authorization)
        conn.execute("UPDATE history SET deleted = 1, updated_at = ? WHERE user_id = ?",
                     (now, user["id"]))
        return {"entries": _history_rows(conn, user["id"])}
