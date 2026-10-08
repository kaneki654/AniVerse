"""
Web push: new-episode alerts on the website even with it closed.

The browser subscribes (js/push.js) and sends the subscription here with the
viewer's My List; every few hours the server checks AniList for new episodes
and pushes a notification for each show that has one. Signed-in viewers'
lists come from their account, so they stay current on their own.

Push messages are encrypted for the browser (RFC 8291, aes128gcm) and the
server identifies itself with VAPID (RFC 8292), both done here with the
`cryptography` package. The VAPID key is made on first use in data/vapid.pem.
"""

import asyncio
import base64
import json
import os
import struct
import time
from typing import Any, Optional
from urllib.parse import urlparse

import httpx
from cryptography.hazmat.primitives import hashes, hmac, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from app import accounts

router = APIRouter(prefix="/api/push")

ANILIST_API = "https://graphql.anilist.co"
CHECK_EVERY = 3 * 3600
MAX_FAILURES = 5

_SCHEMA = """
CREATE TABLE IF NOT EXISTS push_subs (
    endpoint  TEXT PRIMARY KEY,
    p256dh    TEXT NOT NULL,
    auth      TEXT NOT NULL,
    user_id   INTEGER,
    watch     TEXT NOT NULL DEFAULT '[]',
    notified  TEXT NOT NULL DEFAULT '{}',
    created   INTEGER NOT NULL,
    failures  INTEGER NOT NULL DEFAULT 0
);
"""


def _conn():
    accounts.DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    import sqlite3

    conn = sqlite3.connect(accounts.DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.executescript(_SCHEMA)
    return conn


# --- encoding helpers --------------------------------------------------------------------

def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def unb64u(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _hmac(key: bytes, data: bytes) -> bytes:
    h = hmac.HMAC(key, hashes.SHA256())
    h.update(data)
    return h.finalize()


def _hkdf(salt: bytes, ikm: bytes, info: bytes, length: int) -> bytes:
    """HKDF-SHA256, one block (every length used here is at most 32)."""
    prk = _hmac(salt, ikm)
    return _hmac(prk, info + b"\x01")[:length]


def _raw_public(key: ec.EllipticCurvePublicKey) -> bytes:
    return key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


# --- VAPID -----------------------------------------------------------------------------------

_vapid: Optional[ec.EllipticCurvePrivateKey] = None


def vapid_key() -> ec.EllipticCurvePrivateKey:
    global _vapid
    if _vapid is None:
        path = accounts.DATA_DIR / "vapid.pem"
        try:
            loaded = serialization.load_pem_private_key(path.read_bytes(), password=None)
            assert isinstance(loaded, ec.EllipticCurvePrivateKey)
            _vapid = loaded
        except (OSError, ValueError, AssertionError):
            _vapid = ec.generate_private_key(ec.SECP256R1())
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(_vapid.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                  serialization.NoEncryption()))
            path.chmod(0o600)
    return _vapid


def public_key() -> str:
    """The applicationServerKey browsers subscribe with."""
    return b64u(_raw_public(vapid_key().public_key()))


def vapid_header(endpoint: str, now: Optional[int] = None) -> str:
    parts = urlparse(endpoint)
    claims = {
        "aud": f"{parts.scheme}://{parts.netloc}",
        "exp": (now or int(time.time())) + 12 * 3600,
        "sub": os.environ.get("ANIVERSE_PUSH_CONTACT") or "mailto:admin@aniverse.local",
    }
    head = b64u(json.dumps({"typ": "JWT", "alg": "ES256"}, separators=(",", ":")).encode())
    body = b64u(json.dumps(claims, separators=(",", ":")).encode())
    signing = f"{head}.{body}".encode()
    r, s = decode_dss_signature(vapid_key().sign(signing, ec.ECDSA(hashes.SHA256())))
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"vapid t={head}.{body}.{b64u(sig)}, k={public_key()}"


# --- RFC 8291 message encryption -------------------------------------------------------------

def encrypt(payload: bytes, p256dh: str, auth: str, *,
            server_key: Optional[ec.EllipticCurvePrivateKey] = None, salt: Optional[bytes] = None,
            record_size: int = 4096) -> bytes:
    """Encrypt `payload` for one browser subscription (aes128gcm, one record).
    `server_key` and `salt` are only passed by tests, to match RFC 8291's example."""
    ua_public = unb64u(p256dh)
    auth_secret = unb64u(auth)
    server_key = server_key or ec.generate_private_key(ec.SECP256R1())
    salt = salt or os.urandom(16)
    as_public = _raw_public(server_key.public_key())
    ua_key = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), ua_public)
    shared = server_key.exchange(ec.ECDH(), ua_key)
    ikm = _hkdf(auth_secret, shared, b"WebPush: info\x00" + ua_public + as_public, 32)
    cek = _hkdf(salt, ikm, b"Content-Encoding: aes128gcm\x00", 16)
    nonce = _hkdf(salt, ikm, b"Content-Encoding: nonce\x00", 12)
    cipher = AESGCM(cek).encrypt(nonce, payload + b"\x02", None)  # \x02: last record, no padding
    return salt + struct.pack("!IB", record_size, len(as_public)) + as_public + cipher


async def send(sub: dict, message: dict, client: httpx.AsyncClient) -> int:
    """Push one message; returns the push service's HTTP status."""
    body = encrypt(json.dumps(message).encode(), sub["p256dh"], sub["auth"])
    r = await client.post(sub["endpoint"], content=body, headers={
        "TTL": "86400",
        "Urgency": "normal",
        "Content-Encoding": "aes128gcm",
        "Content-Type": "application/octet-stream",
        "Authorization": vapid_header(sub["endpoint"]),
    })
    return r.status_code


# --- subscriptions --------------------------------------------------------------------------

class Keys(BaseModel):
    p256dh: str
    auth: str


class Subscription(BaseModel):
    endpoint: str
    keys: Keys


class WatchItem(BaseModel):
    anime_id: str
    seen_episode: int = 0


class SubscribeBody(BaseModel):
    subscription: Subscription
    watch: list[WatchItem] = []


class Endpoint(BaseModel):
    endpoint: str


def _check_endpoint(url: str) -> None:
    # Push services are https; anything else is not a subscription.
    if not url.startswith("https://") or len(url) > 1000:
        raise HTTPException(status_code=400, detail="Not a push subscription")


@router.get("/key")
def get_key():
    return {"publicKey": public_key()}


@router.post("/subscribe")
def subscribe(body: SubscribeBody, authorization: Optional[str] = Header(None)):
    _check_endpoint(body.subscription.endpoint)
    user_id = None
    if authorization:
        try:
            with accounts._db() as conn:
                user_id = accounts._session_user(conn, authorization)["id"]
        except HTTPException:
            user_id = None
    watch = json.dumps([w.model_dump() for w in body.watch[:500]])
    with _conn() as conn:
        conn.execute(
            "INSERT INTO push_subs (endpoint, p256dh, auth, user_id, watch, created) VALUES (?, ?, ?, ?, ?, ?)"
            " ON CONFLICT(endpoint) DO UPDATE SET p256dh = excluded.p256dh, auth = excluded.auth,"
            " user_id = COALESCE(excluded.user_id, push_subs.user_id), watch = excluded.watch, failures = 0",
            (body.subscription.endpoint, body.subscription.keys.p256dh, body.subscription.keys.auth,
             user_id, watch, int(time.time())),
        )
    return {"ok": True}


@router.post("/unsubscribe")
def unsubscribe(body: Endpoint):
    with _conn() as conn:
        conn.execute("DELETE FROM push_subs WHERE endpoint = ?", (body.endpoint,))
    return {"ok": True}


@router.post("/test")
async def test_push(body: Endpoint):
    """A test notification to one subscription, from Settings."""
    with _conn() as conn:
        row = conn.execute("SELECT * FROM push_subs WHERE endpoint = ?", (body.endpoint,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Not subscribed")
    async with httpx.AsyncClient(timeout=15) as client:
        status = await send(dict(row), {"title": "AniVerse", "body": "Alerts are on. New episodes will show up here.",
                                        "url": "/mylist", "tag": "test"}, client)
    return {"ok": 200 <= status < 300, "status": status}


# --- the check ------------------------------------------------------------------------------

def _aired(media: dict) -> Optional[int]:
    """Episodes out, the way the app and the alert job count them."""
    nxt = media.get("nextAiringEpisode")
    if nxt and isinstance(nxt.get("episode"), int):
        return max(0, nxt["episode"] - 1)
    if media.get("status") == "FINISHED" and media.get("episodes"):
        return int(media["episodes"])
    return None


async def _fetch(client: httpx.AsyncClient, ids: list[int]) -> dict[int, dict]:
    out: dict[int, dict] = {}
    query = ("query ($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) "
             "{ id status episodes nextAiringEpisode { episode } title { english romaji } } } }")
    for i in range(0, len(ids), 50):
        r = await client.post(ANILIST_API, json={"query": query, "variables": {"ids": ids[i:i + 50]}})
        if r.status_code != 200:
            continue
        for m in ((r.json().get("data") or {}).get("Page") or {}).get("media") or []:
            out[m["id"]] = m
    return out


def _watch_of(conn, row) -> list[dict]:
    if row["user_id"]:
        entries = accounts._watchlist_rows(conn, row["user_id"])
        return [{"anime_id": e["anime_id"], "seen_episode": e["seen_episode"]} for e in entries if not e.get("deleted")]
    try:
        return json.loads(row["watch"] or "[]")
    except ValueError:
        return []


async def check_once(client: httpx.AsyncClient, sender=send) -> int:
    """One pass over every subscription. Returns how many alerts went out."""
    with _conn() as conn:
        subs = [dict(r) for r in conn.execute("SELECT * FROM push_subs").fetchall()]
        with accounts._db() as aconn:
            watches = {s["endpoint"]: _watch_of(aconn, s) for s in subs}
    ids = sorted({int(w["anime_id"]) for ws in watches.values() for w in ws if str(w.get("anime_id", "")).isdigit()})
    if not ids:
        return 0
    media = await _fetch(client, ids)
    sent = 0
    for s in subs:
        notified: dict[str, int] = json.loads(s["notified"] or "{}")
        changed = False
        for w in watches[s["endpoint"]]:
            m = media.get(int(w["anime_id"])) if str(w["anime_id"]).isdigit() else None
            if not m:
                continue
            aired = _aired(m)
            if aired is None or aired <= int(w.get("seen_episode") or 0) or aired <= notified.get(str(w["anime_id"]), 0):
                continue
            title = (m.get("title") or {}).get("english") or (m.get("title") or {}).get("romaji") or "AniVerse"
            fresh = aired - max(int(w.get("seen_episode") or 0), notified.get(str(w["anime_id"]), 0))
            status = await sender(s, {
                "title": title,
                "body": f"{fresh} new episodes, up to episode {aired}" if fresh > 1 else f"Episode {aired} is out",
                "url": f"/watch/{w['anime_id']}/{aired}",
                "tag": f"ep-{w['anime_id']}",
            }, client)
            if status in (404, 410):  # the browser dropped the subscription
                with _conn() as conn:
                    conn.execute("DELETE FROM push_subs WHERE endpoint = ?", (s["endpoint"],))
                changed = False
                break
            if 200 <= status < 300:
                notified[str(w["anime_id"])] = aired
                changed = True
                sent += 1
            else:
                with _conn() as conn:
                    conn.execute("UPDATE push_subs SET failures = failures + 1 WHERE endpoint = ?", (s["endpoint"],))
                    conn.execute("DELETE FROM push_subs WHERE endpoint = ? AND failures >= ?", (s["endpoint"], MAX_FAILURES))
        if changed:
            with _conn() as conn:
                conn.execute("UPDATE push_subs SET notified = ?, failures = 0 WHERE endpoint = ?",
                             (json.dumps(notified), s["endpoint"]))
    return sent


async def checker_loop() -> None:
    """Runs for the life of the server: a check a few minutes after start, then every few hours."""
    await asyncio.sleep(300)
    while True:
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                n = await check_once(client)
            if n:
                print(f"Web push: sent {n} new-episode alert{'s' if n != 1 else ''}")
        except Exception as e:  # keep the loop alive whatever happens
            print(f"Web push check failed: {e}")
        await asyncio.sleep(CHECK_EVERY)


def summary() -> dict[str, Any]:
    with _conn() as conn:
        return {"subscriptions": conn.execute("SELECT COUNT(*) FROM push_subs").fetchone()[0]}
