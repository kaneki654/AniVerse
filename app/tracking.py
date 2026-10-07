"""
AniList and MyAnimeList tracking: finishing an episode here moves your list
there, from the app and the website alike, because it runs on the server when
watch history syncs.

Both services only work once you register an API client with them and give
its ID to this server, since neither allows anonymous list updates:

- AniList: create a client at https://anilist.co/settings/developer with the
  redirect URL https://anilist.co/api/v2/oauth/pin, and set
  ANIVERSE_ANILIST_CLIENT_ID. The "pin" flow shows the user a token to paste
  back, so it works whatever address this server has today.
- MyAnimeList: create an app at https://myanimelist.net/apiconfig with the
  redirect URL <this server>/api/tracking/mal/callback, and set
  ANIVERSE_MAL_CLIENT_ID (plus ANIVERSE_MAL_CLIENT_SECRET for a "web" app).
  Its redirect is fixed, so it wants the server on a stable address.

Progress only ever moves forward: rewatching episode 3 never pulls a list
entry back from episode 12.
"""

import os
import secrets
import threading
import time
from typing import Optional

import httpx
from fastapi import APIRouter, Header, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

import anime_meta
from app.accounts import _db, _session_user

router = APIRouter(prefix="/api/tracking")

ANILIST_API = "https://graphql.anilist.co"
MAL_AUTH = "https://myanimelist.net/v1/oauth2"
MAL_API = "https://api.myanimelist.net/v2"


def _env(name: str) -> Optional[str]:
    return (os.environ.get(name) or "").strip() or None


def anilist_client_id() -> Optional[str]:
    return _env("ANIVERSE_ANILIST_CLIENT_ID")


def mal_client_id() -> Optional[str]:
    return _env("ANIVERSE_MAL_CLIENT_ID")


# --- config and status -----------------------------------------------------------

@router.get("/config")
def tracking_config():
    aid = anilist_client_id()
    return {
        "anilist": {
            "enabled": bool(aid),
            "authorize_url": f"https://anilist.co/api/v2/oauth/authorize?client_id={aid}&response_type=token" if aid else None,
        },
        "mal": {"enabled": bool(mal_client_id())},
    }


@router.get("")
def tracking_status(authorization: Optional[str] = Header(None)):
    with _db() as conn:
        user = _session_user(conn, authorization)
        rows = conn.execute("SELECT service, account_name FROM tracking WHERE user_id = ?", (user["id"],)).fetchall()
    linked = {r["service"]: r["account_name"] for r in rows}
    return {s: {"connected": s in linked, "account": linked.get(s)} for s in ("anilist", "mal")}


@router.delete("/{service}")
def tracking_disconnect(service: str, authorization: Optional[str] = Header(None)):
    if service not in ("anilist", "mal"):
        raise HTTPException(status_code=404, detail="Unknown service")
    with _db() as conn:
        user = _session_user(conn, authorization)
        conn.execute("DELETE FROM tracking WHERE user_id = ? AND service = ?", (user["id"], service))
    return {"ok": True}


# --- AniList -------------------------------------------------------------------------

class AniListToken(BaseModel):
    token: str


async def _anilist(token: str, query: str, variables: dict) -> dict:
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(ANILIST_API, json={"query": query, "variables": variables},
                              headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    body = r.json()
    if r.status_code != 200 or body.get("errors"):
        raise HTTPException(status_code=400, detail="AniList rejected the token")
    return body["data"]


@router.post("/anilist")
async def anilist_connect(body: AniListToken, authorization: Optional[str] = Header(None)):
    """Store an AniList token pasted from the pin page, after checking it works."""
    token = body.token.strip()
    if not 20 < len(token) < 3000:
        raise HTTPException(status_code=400, detail="That doesn't look like an AniList token")
    with _db() as conn:
        user = _session_user(conn, authorization)
    viewer = (await _anilist(token, "query { Viewer { id name } }", {})).get("Viewer") or {}
    with _db() as conn:
        # `refresh` holds the AniList user id: AniList tokens last a year and have no refresh token.
        conn.execute(
            "INSERT INTO tracking (user_id, service, token, refresh, expires_at, account_name)"
            " VALUES (?, 'anilist', ?, ?, ?, ?) ON CONFLICT(user_id, service) DO UPDATE SET"
            " token = excluded.token, refresh = excluded.refresh, expires_at = excluded.expires_at,"
            " account_name = excluded.account_name",
            (user["id"], token, str(viewer.get("id") or ""), int(time.time()) + 365 * 86400, viewer.get("name")))
    return {"connected": True, "account": viewer.get("name")}


async def _anilist_progress(token: str, viewer_id: str, anilist_id: int, episode: int, total: Optional[int]):
    current = 0
    if viewer_id:
        try:
            data = await _anilist(token, "query ($u: Int, $m: Int) { MediaList (userId: $u, mediaId: $m) { progress } }",
                                  {"u": int(viewer_id), "m": anilist_id})
            current = ((data or {}).get("MediaList") or {}).get("progress") or 0
        except HTTPException:
            current = 0  # not on the list yet: AniList answers "not found"
    if episode <= current:
        return
    status = "COMPLETED" if total and episode >= total else "CURRENT"
    await _anilist(token, "mutation ($m: Int, $p: Int, $s: MediaListStatus) {"
                          " SaveMediaListEntry (mediaId: $m, progress: $p, status: $s) { id } }",
                   {"m": anilist_id, "p": episode, "s": status})


# --- MyAnimeList ------------------------------------------------------------------------

_pending_mal: dict = {}          # state -> (user_id, verifier, redirect_uri, expires)
_pending_lock = threading.Lock()


def _public_base(request: Request) -> str:
    configured = _env("ANIVERSE_PUBLIC_URL")
    if configured:
        return configured.rstrip("/")
    host = request.headers.get("x-forwarded-host") or request.headers.get("host") or request.url.netloc
    scheme = request.headers.get("x-forwarded-proto") or ("https" if "trycloudflare" in host else request.url.scheme)
    return f"{scheme}://{host}"


@router.post("/mal/start")
def mal_start(request: Request, authorization: Optional[str] = Header(None)):
    """A one-time sign-in link for MyAnimeList. The link carries only a random
    state, never the session token, so it is safe in browser history."""
    client_id = mal_client_id()
    if not client_id:
        raise HTTPException(status_code=503, detail="MyAnimeList is not set up on this server")
    with _db() as conn:
        user = _session_user(conn, authorization)
    state = secrets.token_urlsafe(24)
    verifier = secrets.token_urlsafe(64)[:100]  # PKCE "plain": the challenge is the verifier
    redirect_uri = f"{_public_base(request)}/api/tracking/mal/callback"
    with _pending_lock:
        now = time.time()
        for k in [k for k, v in _pending_mal.items() if v[3] < now]:
            _pending_mal.pop(k, None)
        _pending_mal[state] = (user["id"], verifier, redirect_uri, now + 600)
    url = str(httpx.URL(f"{MAL_AUTH}/authorize", params={
        "response_type": "code", "client_id": client_id, "state": state, "redirect_uri": redirect_uri,
        "code_challenge": verifier, "code_challenge_method": "plain",
    }))
    return {"url": url}


def _page(title: str, text: str) -> HTMLResponse:
    return HTMLResponse(
        "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>"
        "<body style='background:#0d0709;color:#f2e8d5;font:16px monospace;display:grid;place-items:center;"
        "min-height:90vh;text-align:center'><div><h2 style='color:#d10a1a'>" + title + "</h2><p>" + text +
        "</p><p><a style='color:#ff4d57' href='/account'>Back to AniVerse</a></p></div>")


@router.get("/mal/callback")
async def mal_callback(code: str = "", state: str = ""):
    with _pending_lock:
        pending = _pending_mal.pop(state, None)
    if not pending or pending[3] < time.time() or not code:
        return _page("Link expired", "Start the MyAnimeList connection again from your account page.")
    user_id, verifier, redirect_uri, _ = pending
    tokens = await _mal_token({"grant_type": "authorization_code", "code": code,
                               "code_verifier": verifier, "redirect_uri": redirect_uri})
    if not tokens:
        return _page("MyAnimeList said no", "The sign-in could not be completed. Try again.")
    async with httpx.AsyncClient(timeout=15) as client:
        me = await client.get(f"{MAL_API}/users/@me", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    name = (me.json() if me.status_code == 200 else {}).get("name")
    _store_mal(user_id, tokens, name)
    return _page("MyAnimeList connected", "Episodes you finish will now update your list. You can close this page.")


async def _mal_token(data: dict) -> Optional[dict]:
    data = {**data, "client_id": mal_client_id()}
    secret = _env("ANIVERSE_MAL_CLIENT_SECRET")
    if secret:
        data["client_secret"] = secret
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(f"{MAL_AUTH}/token", data=data)
    return r.json() if r.status_code == 200 else None


def _store_mal(user_id: int, tokens: dict, name: Optional[str]) -> None:
    with _db() as conn:
        conn.execute(
            "INSERT INTO tracking (user_id, service, token, refresh, expires_at, account_name)"
            " VALUES (?, 'mal', ?, ?, ?, ?) ON CONFLICT(user_id, service) DO UPDATE SET"
            " token = excluded.token, refresh = excluded.refresh, expires_at = excluded.expires_at,"
            " account_name = COALESCE(excluded.account_name, tracking.account_name)",
            (user_id, tokens["access_token"], tokens.get("refresh_token"),
             int(time.time()) + int(tokens.get("expires_in") or 3600), name))


async def _mal_progress(user_id: int, row, mal_id: int, episode: int, total: Optional[int]):
    token = row["token"]
    if (row["expires_at"] or 0) < time.time() + 60 and row["refresh"]:
        fresh = await _mal_token({"grant_type": "refresh_token", "refresh_token": row["refresh"]})
        if not fresh:
            return
        _store_mal(user_id, fresh, None)
        token = fresh["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(f"{MAL_API}/anime/{mal_id}", params={"fields": "my_list_status,num_episodes"}, headers=headers)
        info = r.json() if r.status_code == 200 else {}
        current = (info.get("my_list_status") or {}).get("num_episodes_watched") or 0
        total = info.get("num_episodes") or total
        if episode <= current:
            return
        status = "completed" if total and episode >= total else "watching"
        await client.patch(f"{MAL_API}/anime/{mal_id}/my_list_status", headers=headers,
                           data={"num_watched_episodes": episode, "status": status})


# --- the hook from history sync --------------------------------------------------------

async def sync_progress(user_id: int, finished: dict[str, int]) -> None:
    """Move linked lists forward to the furthest finished episode of each anime.
    Runs after a history sync answers, so a slow tracker never delays it."""
    if not finished:
        return
    with _db() as conn:
        rows = {r["service"]: r for r in conn.execute("SELECT * FROM tracking WHERE user_id = ?", (user_id,))}
    if not rows:
        return
    for anime_id, episode in finished.items():
        try:
            media = await anime_meta.fetch_media(anime_id) or {}
            total = media.get("episodes")
            if "anilist" in rows:
                await _anilist_progress(rows["anilist"]["token"], rows["anilist"]["refresh"] or "",
                                        int(anime_id), episode, total)
            if "mal" in rows and media.get("idMal"):
                await _mal_progress(user_id, rows["mal"], int(media["idMal"]), episode, total)
        except (httpx.HTTPError, HTTPException, ValueError, KeyError) as e:
            print(f"Tracking update failed for user {user_id}, anime {anime_id}: {e}")
