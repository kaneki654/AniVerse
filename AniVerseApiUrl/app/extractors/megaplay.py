"""Shared extractor for the megaplay-family embeds.

megaplay.buzz, vidwish.live and the `*/megaplay/stream/...` proxies all expose
the same `stream/getSources?id=<id>&type=<sub|dub>` endpoint. AniWatch reaches
them through its base64 `data-hash` server links, GogoAnime through a
`newplayer.php` wrapper that iframes the same embed.

Each host token-locks its CDN to its *own* Referer, so the resolved stream
carries the referer that unlocks it rather than a hardcoded one.
"""

import base64
import json
import re
import time
import urllib.parse
from typing import Any, Dict, Optional

import httpx
from Crypto.Cipher import AES

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

# Hosts that serve the megaplay getSources API directly.
NATIVE_HOSTS = ("megaplay.buzz", "vidwish.live")

# getSources stopped returning a plaintext `sources` object and now ships the
# file URL as `enc`: base64url AES-256-CBC. The key and IV are the ones
# megaplay's own newclient.min.js hands to WebCrypto -- the key is the seed
# below zero-padded to 32 bytes, which is what `new Uint8Array(32)` does there.
_ENC_KEY_SEED = "i?LMTAx0Q6,:}50U"
_ENC_IV = "W0;27ToaUpl_P%'c"

# Rotating the key is how the site breaks us, so the seed/IV are re-read from
# newclient.min.js when the built-in pair stops decrypting. The cooldown is
# what keeps that from becoming a request per episode if the player script
# stops being parseable, while still letting a refresh that failed on a
# network blip be retried instead of giving up for the whole process.
_enc_keys: Optional[tuple] = None
_enc_keys_next_try = 0.0
_ENC_KEY_RETRY_SECONDS = 300

# The two `(new TextEncoder).encode("...")` literals inside newclient's segment
# module, in source order: the importKey seed, then the IV.
_ENC_MODULE_RE = re.compile(r'var \w+=/\\/segment\\/.*?SegmentDecrypt', re.S)
_ENC_LITERAL_RE = re.compile(r'encode\("((?:[^"\\]|\\.)*)"\)')


def _aes_key(seed: str) -> bytes:
    """The 32-byte AES key newclient derives from a seed string."""
    return seed.encode()[:32].ljust(32, b"\x00")


def _decrypt_enc(enc: str, seed: str, iv: str) -> Optional[Any]:
    """Decrypt an `enc` blob into the JSON it carries, or None."""
    try:
        padded = enc + "=" * (-len(enc) % 4)
        raw = AES.new(_aes_key(seed), AES.MODE_CBC, iv.encode()).decrypt(
            base64.urlsafe_b64decode(padded))
        if not raw:
            return None
        pad = raw[-1]
        if not 1 <= pad <= 16 or pad > len(raw):
            return None
        return json.loads(raw[:-pad].decode("utf-8"))
    except Exception:
        return None


async def _fetch_enc_keys(client: httpx.AsyncClient, api_host: str) -> Optional[tuple]:
    """The seed/IV pair megaplay's player is currently using, or None."""
    try:
        resp = await client.get(f"https://{api_host}/lib/newclient.min.js",
                                headers={"User-Agent": UA,
                                         "Referer": f"https://{api_host}/"})
        if resp.status_code != 200:
            return None
        module = _ENC_MODULE_RE.search(resp.text)
        if not module:
            return None
        found = _ENC_LITERAL_RE.findall(module.group(0))
        if len(found) < 2:
            return None
        seed, iv = found[0], found[1]
        # A wrong capture is worse than no refresh: the IV has to be a block.
        return (seed, iv) if len(iv.encode()) == 16 and seed else None
    except Exception as e:
        print(f"Megaplay key refresh failed ({api_host}): {type(e).__name__}: {e}")
        return None


async def decrypt_sources(client: httpx.AsyncClient, api_host: str,
                          enc: str) -> Optional[Any]:
    """`enc` as the payload it encrypts, re-reading the key if ours is stale."""
    global _enc_keys, _enc_keys_next_try

    for seed, iv in filter(None, (_enc_keys, (_ENC_KEY_SEED, _ENC_IV))):
        data = _decrypt_enc(enc, seed, iv)
        if data is not None:
            return data

    now = time.monotonic()
    if now < _enc_keys_next_try:
        return None
    _enc_keys_next_try = now + _ENC_KEY_RETRY_SECONDS

    keys = await _fetch_enc_keys(client, api_host)
    if not keys:
        print(f"Megaplay: cannot decrypt enc payload from {api_host}")
        return None
    data = _decrypt_enc(enc, *keys)
    if data is None:
        print(f"Megaplay: key read from {api_host} still does not decrypt")
        return None
    print(f"Megaplay: picked up a rotated enc key from {api_host}")
    _enc_keys = keys
    return data


def _as_sources(payload: Any) -> Optional[Dict[str, Any]]:
    """Normalise a decrypted payload to the {"file": ...} shape."""
    if isinstance(payload, list):
        payload = payload[0] if payload else None
    if isinstance(payload, dict) and payload.get("file"):
        return payload
    return None


# .../stream/s-2/<id>/<sub|dub>  — optionally behind a /megaplay/ or /mp/ proxy path.
EMBED_RE = re.compile(
    r'https?://(?P<host>[^/]+)/(?:[^/]+/)*?stream/s-\d+/(?P<id>\d+)/(?P<type>sub|dub)\b',
    re.I,
)


def match_megaplay(embed_url: str) -> Optional[Dict[str, str]]:
    """Return {host, api_host, id, type} for a megaplay-family embed, else None."""
    m = EMBED_RE.search(embed_url or "")
    if not m:
        return None
    host = m.group("host").lower()

    # A proxy host (e.g. 1anime.site/megaplay/...) still talks to megaplay.buzz.
    api_host = host
    if not any(host.endswith(h) for h in NATIVE_HOSTS):
        path = urllib.parse.urlparse(embed_url).path.lower()
        api_host = "vidwish.live" if "vidwish" in path else "megaplay.buzz"

    return {"host": host, "api_host": api_host, "id": m.group("id"), "type": m.group("type").lower()}


# newclient.min.js rewrites every getSources call to getSourcesNew, so that is
# the endpoint the site actually maintains; the old one is tried as a fallback.
_SOURCE_ENDPOINTS = ("getSourcesNew", "getSources")


async def fetch_sources(client: httpx.AsyncClient, mega: Dict[str, str]) -> Optional[Dict[str, Any]]:
    """Call getSources on the embed's own host.

    The payload is normalised so callers always see a plaintext `sources`
    dict, whether the host sent one or shipped the file URL as `enc`.
    """
    api_host = mega["api_host"]
    eid, cat = mega["id"], mega["type"]
    headers = {
        "User-Agent": UA,
        "Referer": f"https://{api_host}/stream/s-2/{eid}/{cat}",
        "X-Requested-With": "XMLHttpRequest",
    }

    data = None
    for endpoint in _SOURCE_ENDPOINTS:
        url = f"https://{api_host}/stream/{endpoint}?id={eid}&type={cat}"
        try:
            resp = await client.get(url, headers=headers)
        except Exception as e:
            print(f"Megaplay {endpoint} failed ({api_host}/{eid}/{cat}): "
                  f"{type(e).__name__}: {e}")
            continue
        if resp.status_code != 200:
            continue
        try:
            payload = resp.json()
        except Exception:
            continue
        if isinstance(payload, dict):
            data = payload
            break

    if data is None:
        return None

    if not _as_sources(data.get("sources")) and data.get("enc"):
        decrypted = await decrypt_sources(client, api_host, data["enc"])
        sources = _as_sources(decrypted)
        if not sources:
            return None
        data["sources"] = sources

    return data


def _file_of(data: Dict[str, Any]) -> Optional[str]:
    sources = (data or {}).get("sources") or {}
    return sources.get("file") if isinstance(sources, dict) else None


async def fetch_sources_verified(client: httpx.AsyncClient, mega: Dict[str, str]) -> Optional[Dict[str, Any]]:
    """getSources, but a dub request must return audio that differs from the sub.

    Several catalogue entries expose a `-dub` route whose embed still resolves
    to the sub file; getSources happily echoes `type=dub` back. Serving that
    would label sub audio as a dub, so cross-check and drop it instead.
    """
    data = await fetch_sources(client, mega)
    if not data:
        return None

    if mega.get("type") == "dub":
        file_url = _file_of(data)
        sub_data = await fetch_sources(client, {**mega, "type": "sub"})
        sub_file = _file_of(sub_data) if sub_data else None
        if file_url and sub_file and file_url == sub_file:
            print(f"Megaplay: {mega['api_host']}/{mega['id']} dub == sub file -> no real dub")
            return None

    return data


async def check_playable(client: httpx.AsyncClient, file_url: str, referer: str) -> bool:
    """True when the CDN actually serves the manifest for this referer.

    vidwish.live hands out master.m3u8 URLs that its CDN then 403s, so a
    resolved URL is not on its own evidence of a playable stream.
    """
    try:
        resp = await client.get(file_url, headers={"User-Agent": UA, "Referer": referer})
    except Exception:
        return False
    return resp.status_code == 200 and "#EXTM3U" in resp.text


def build_result(data: Dict[str, Any], mega: Dict[str, str], server_name: str) -> Dict[str, Any]:
    """Turn a getSources payload into the provider {streams, subtitles} shape."""
    sources = data.get("sources") or {}
    file_url = sources.get("file") if isinstance(sources, dict) else None
    if not file_url:
        return {"streams": [], "subtitles": []}

    referer = f"https://{mega['api_host']}/"

    subtitles = []
    for track in data.get("tracks") or []:
        if not isinstance(track, dict) or not track.get("file"):
            continue
        if (track.get("kind") or "").lower() == "thumbnails":
            continue
        label = re.split(r'\s*\(-\s*', track.get("label", "") or "")[0].strip()
        subtitles.append({
            "url": track["file"],
            "lang": label or "English",
            "kind": "captions",
            "referer": referer,
        })

    return {
        "intro": _skip_marker(data.get("intro")),
        "outro": _skip_marker(data.get("outro")),
        "streams": [{
            "quality": "auto",
            "url": file_url,
            "server": server_name,
            "category": mega["type"],
            "referer": referer,
        }],
        "subtitles": subtitles,
    }


def _skip_marker(marker):
    """A skip range, or None when the site has no data for this episode.

    Megaplay reports "no markers" as {"start": 0, "end": 0}. Passed through
    as-is, the player's `t >= start && t <= end` test matches at t=0 and flashes
    the button at the start of every episode that has no intro.
    """
    if not isinstance(marker, dict):
        return None
    start = marker.get("start") or 0
    end = marker.get("end") or 0
    if end <= start:
        return None
    return {"start": start, "end": end}
