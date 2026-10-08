"""
Watch parties: friends watching the same episode in step, from the website or
the app, through one WebSocket room per party code.

Everyone in a room is equal: whoever plays, pauses, seeks or changes episode
sends the new state, and the server passes it to the others. Each state
carries the server time it was set at, and every message the server's "now",
so a member can work out where playback should be without trusting the clocks
on anyone's device. Rooms live in memory and vanish when the last member leaves.

Limits keep a room usable when someone misbehaves: a few sockets per address,
a cap on how fast state changes and chat can be sent, and names unique within
a room (a second "Kai" becomes "Kai (2)").
"""

import asyncio
import re
import time
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()

CODE_RE = re.compile(r"^[A-Z0-9]{4,8}$")
MAX_MEMBERS = 20
MAX_ROOMS = 500
MAX_PER_IP = 8


class _Bucket:
    """Token bucket: `rate` messages a second on average, bursts up to `burst`."""

    def __init__(self, rate: float, burst: float) -> None:
        self.rate, self.burst = rate, burst
        self.tokens, self.at = burst, time.monotonic()

    def take(self) -> bool:
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.at) * self.rate)
        self.at = now
        if self.tokens < 1:
            return False
        self.tokens -= 1
        return True


_per_ip: dict[str, int] = {}


def _ip(ws: WebSocket) -> str:
    # cloudflared connects from localhost; Cloudflare passes the real address on.
    return (ws.headers.get("cf-connecting-ip")
            or ws.headers.get("x-forwarded-for", "").split(",")[0].strip()
            or (ws.client.host if ws.client else "unknown"))


def _unique(room: "Room", name: str) -> str:
    taken = set(room.members.values())
    if name not in taken:
        return name
    n = 2
    while f"{name} ({n})" in taken:
        n += 1
    return f"{name} ({n})"


class Room:
    def __init__(self) -> None:
        self.members: dict[WebSocket, str] = {}
        self.state: dict[str, Any] | None = None


_rooms: dict[str, Room] = {}


async def _send(ws: WebSocket, message: dict[str, Any]) -> None:
    try:
        await ws.send_json({**message, "now": time.time()})
    except (RuntimeError, WebSocketDisconnect):
        pass  # gone; its own handler cleans up


async def _broadcast(room: Room, message: dict[str, Any], skip: WebSocket | None = None) -> None:
    await asyncio.gather(*(_send(ws, message) for ws in list(room.members) if ws is not skip))


def _members(room: Room) -> list[str]:
    return sorted(room.members.values())


@router.websocket("/ws/party/{code}")
async def party(ws: WebSocket, code: str, name: str = "Guest"):
    code = code.upper()
    if not CODE_RE.match(code):
        await ws.close(code=4400)
        return
    ip = _ip(ws)
    if _per_ip.get(ip, 0) >= MAX_PER_IP:
        await ws.close(code=4429)
        return
    room = _rooms.get(code)
    if room is None:
        if len(_rooms) >= MAX_ROOMS:
            await ws.close(code=4429)
            return
        room = _rooms[code] = Room()
    if len(room.members) >= MAX_MEMBERS:
        await ws.close(code=4413)
        return

    await ws.accept()
    _per_ip[ip] = _per_ip.get(ip, 0) + 1
    me = _unique(room, re.sub(r"[^\w .-]", "", name)[:24].strip() or "Guest")
    room.members[ws] = me
    states, chats = _Bucket(8, 16), _Bucket(1, 3)
    await _send(ws, {"type": "hello", "state": room.state, "members": _members(room), "you": me})
    await _broadcast(room, {"type": "members", "members": _members(room), "joined": me}, skip=ws)
    try:
        while True:
            msg = await ws.receive_json()
            kind = msg.get("type") if isinstance(msg, dict) else None
            if kind == "state":
                if not states.take():
                    continue  # faster than any person seeks; drop it
                try:
                    state = {
                        "anime": str(msg["anime"])[:16],
                        "ep": int(msg["ep"]),
                        "category": "dub" if msg.get("category") == "dub" else "sub",
                        "playing": bool(msg.get("playing")),
                        "t": max(0.0, float(msg.get("t") or 0)),
                        "at": time.time(),
                        "by": me,
                    }
                except (KeyError, TypeError, ValueError):
                    continue
                room.state = state
                await _broadcast(room, {"type": "state", "state": state}, skip=ws)
            elif kind == "chat":
                if not chats.take():
                    await _send(ws, {"type": "chat", "name": "", "text": "Slow down a little."})
                    continue
                text = str(msg.get("text") or "").strip()[:200]
                if text:
                    await _broadcast(room, {"type": "chat", "name": me, "text": text})
            elif kind == "ping":
                await _send(ws, {"type": "pong"})
    except (WebSocketDisconnect, RuntimeError, ValueError):
        pass
    finally:
        _per_ip[ip] = _per_ip.get(ip, 1) - 1
        if _per_ip[ip] <= 0:
            _per_ip.pop(ip, None)
        room.members.pop(ws, None)
        if room.members:
            await _broadcast(room, {"type": "members", "members": _members(room), "left": me})
        else:
            _rooms.pop(code, None)
