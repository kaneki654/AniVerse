"""Web push (app/webpush.py): the encryption matches RFC 8291's worked example,
VAPID headers verify, and the new-episode check sends what it should.

Run with: python3 -m pytest -q tests/test_webpush.py
"""

import asyncio
import json
import pathlib
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from fastapi.testclient import TestClient

from app import accounts, webpush
from app.main import app

# RFC 8291, section 5.
BODY = ("DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml"
        "mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT"
        "pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN")
AUTH = "BTBZMqHH6r4Tts7J_aSIgg"
RECEIVER_PUBLIC = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
SENDER_PRIVATE = "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"


class EncryptionTest(unittest.TestCase):
    def test_matches_the_rfc_example(self):
        expected = webpush.unb64u(BODY)
        sender = ec.derive_private_key(int.from_bytes(webpush.unb64u(SENDER_PRIVATE), "big"), ec.SECP256R1())
        record_size = int.from_bytes(expected[16:20], "big")
        out = webpush.encrypt(b"When I grow up, I want to be a watermelon", RECEIVER_PUBLIC, AUTH,
                              server_key=sender, salt=expected[:16], record_size=record_size)
        self.assertEqual(webpush.b64u(out), webpush.b64u(expected))


class _Isolated(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        d = pathlib.Path(tmp.name)
        for target, name, value in [(accounts, "DB_PATH", d / "a.db"), (accounts, "DATA_DIR", d),
                                    (accounts, "_initialised", False), (accounts, "_registrations", {}),
                                    (webpush, "_vapid", None)]:
            p = patch.object(target, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.dir = d
        self.client = TestClient(app)
        self.addCleanup(self.client.close)

    def subscribe(self, endpoint="https://push.example.net/abc", watch=None, headers=None):
        return self.client.post("/api/push/subscribe", headers=headers or {}, json={
            "subscription": {"endpoint": endpoint, "keys": {"p256dh": RECEIVER_PUBLIC, "auth": AUTH}},
            "watch": watch or [],
        })


class VapidTest(_Isolated):
    def test_header_is_a_valid_es256_jwt(self):
        header = webpush.vapid_header("https://push.example.net/x/y")
        token = header.split("t=")[1].split(",")[0]
        head, body, sig = token.split(".")
        claims = json.loads(webpush.unb64u(body))
        self.assertEqual(claims["aud"], "https://push.example.net")
        raw = webpush.unb64u(sig)
        der = encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
        webpush.vapid_key().public_key().verify(der, f"{head}.{body}".encode(), ec.ECDSA(hashes.SHA256()))
        self.assertIn(f"k={webpush.public_key()}", header)
        self.assertEqual(oct((self.dir / "vapid.pem").stat().st_mode & 0o777), "0o600")

    def test_key_endpoint(self):
        key = self.client.get("/api/push/key").json()["publicKey"]
        self.assertEqual(len(webpush.unb64u(key)), 65)


class CheckTest(_Isolated):
    MEDIA = {154587: {"id": 154587, "status": "RELEASING", "episodes": 28, "nextAiringEpisode": {"episode": 14},
                      "title": {"english": "Frieren", "romaji": "Sousou no Frieren"}}}

    def test_alerts_once_per_new_episode(self):
        self.assertEqual(self.subscribe(watch=[{"anime_id": "154587", "seen_episode": 12}]).status_code, 200)
        sent = []

        async def sender(sub, message, client):
            sent.append(message)
            return 201

        with patch.object(webpush, "_fetch", AsyncMock(return_value=self.MEDIA)):
            self.assertEqual(asyncio.run(webpush.check_once(None, sender)), 1)  # pyright: ignore[reportArgumentType]
            self.assertEqual(asyncio.run(webpush.check_once(None, sender)), 0)  # pyright: ignore[reportArgumentType]
        self.assertEqual(sent[0]["title"], "Frieren")
        self.assertEqual(sent[0]["body"], "Episode 13 is out")
        self.assertEqual(sent[0]["url"], "/watch/154587/13")

    def test_a_gone_subscription_is_dropped(self):
        self.subscribe(watch=[{"anime_id": "154587", "seen_episode": 1}])

        async def gone(sub, message, client):
            return 410

        with patch.object(webpush, "_fetch", AsyncMock(return_value=self.MEDIA)):
            asyncio.run(webpush.check_once(None, gone))  # pyright: ignore[reportArgumentType]
        self.assertEqual(webpush.summary()["subscriptions"], 0)

    def test_signed_in_viewers_use_their_account_list(self):
        r = self.client.post("/api/auth/register", json={"username": "PushFan", "password": "test-password-42"})
        headers = {"Authorization": f"Bearer {r.json()['token']}"}
        self.client.put("/api/watchlist", headers=headers, json={"entries": [
            {"anime_id": "154587", "title": "Frieren", "cover": "", "seen_episode": 10, "updated_at": 1}]})
        self.subscribe(headers=headers)  # no list sent: the account's is used
        sent = []

        async def sender(sub, message, client):
            sent.append(message)
            return 201

        with patch.object(webpush, "_fetch", AsyncMock(return_value=self.MEDIA)):
            asyncio.run(webpush.check_once(None, sender))  # pyright: ignore[reportArgumentType]
        self.assertEqual(sent[0]["body"], "3 new episodes, up to episode 13")

    def test_rejects_non_https_endpoints(self):
        self.assertEqual(self.subscribe(endpoint="http://evil.example/x").status_code, 400)


if __name__ == "__main__":
    unittest.main()
