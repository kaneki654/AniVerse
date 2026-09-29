"""Account routes on the actual web app, using an isolated database.

Run with: python3 -m unittest discover -s tests -p 'test_accounts.py'
"""

import pathlib
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app import accounts
from app.main import app


class AccountRoutesTest(unittest.TestCase):
    def setUp(self):
        storage = tempfile.TemporaryDirectory()
        self.addCleanup(storage.cleanup)
        for name, value in {
            "DB_PATH": pathlib.Path(storage.name) / "accounts.db",
            "_initialised": False,
            "_failed_logins": {},
            "_registrations": {},
        }.items():
            replacement = patch.object(accounts, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.credentials = {"username": "AnimeFan", "password": "test-password-42"}

    def register(self):
        response = self.client.post("/api/auth/register", json=self.credentials)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_account_routes_are_mounted_in_the_web_app(self):
        response = self.client.get("/api/auth/config")
        self.assertEqual(response.status_code, 200)
        self.assertIs(response.json()["password"], True)
        paths = self.client.get("/openapi.json").json()["paths"]
        for route in ("config", "register", "login", "me", "logout"):
            self.assertIn(f"/api/auth/{route}", paths)

    def test_create_sign_in_restore_and_sign_out(self):
        created = self.register()
        self.assertEqual(created["user"]["username"], "AnimeFan")
        self.assertNotIn("password_hash", created["user"])
        response = self.client.post(
            "/api/auth/login",
            json={**self.credentials, "username": " animefan "},
        )
        self.assertEqual(response.status_code, 200, response.text)
        signed_in = response.json()
        self.assertEqual(signed_in["user"]["id"], created["user"]["id"])
        headers = {"Authorization": f"Bearer {signed_in['token']}"}
        response = self.client.get("/api/auth/me", headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["user"], signed_in["user"])
        self.assertEqual(
            self.client.post("/api/auth/logout", headers=headers).status_code, 200
        )
        self.assertEqual(
            self.client.get("/api/auth/me", headers=headers).status_code, 401
        )

    def test_bad_credentials_have_a_clear_error(self):
        self.register()
        for username in ("AnimeFan", "MissingFan"):
            response = self.client.post(
                "/api/auth/login", json={"username": username, "password": "wrong"}
            )
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.json()["detail"], "Wrong username or password")

    def test_duplicate_and_invalid_registrations_do_not_break_login(self):
        self.register()
        duplicate = self.client.post(
            "/api/auth/register", json={**self.credentials, "username": "animefan"}
        )
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(duplicate.json()["detail"], "That username is taken")
        invalid = self.client.post(
            "/api/auth/register", json={"username": "a", "password": "short"}
        )
        self.assertEqual(invalid.status_code, 400)
        self.assertEqual(
            self.client.post("/api/auth/login", json=self.credentials).status_code, 200
        )

    def test_new_session_can_sync_history_and_other_accounts_cannot_read_it(self):
        created = self.register()
        headers = {"Authorization": f"Bearer {created['token']}"}
        history = {
            "entries": [{"anime_id": "123", "episode": 1, "position_ms": 45000,
                         "updated_at": 1000}]
        }
        response = self.client.put("/api/history", json=history, headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["entries"][0]["position_ms"], 45000)
        other = self.client.post(
            "/api/auth/register",
            json={**self.credentials, "username": "OtherFan"},
        ).json()
        response = self.client.get(
            "/api/history", headers={"Authorization": f"Bearer {other['token']}"}
        )
        self.assertEqual(response.json(), {"entries": []})
        self.assertEqual(self.client.get("/api/history").status_code, 401)


if __name__ == "__main__":
    unittest.main()
