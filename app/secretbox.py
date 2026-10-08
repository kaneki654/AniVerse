"""
Secrets at rest: the AniList / MyAnimeList tokens stored for tracking.

Values are sealed with Fernet (AES-128-CBC + HMAC-SHA256) before they reach
the database and opened when read. The key comes from ANIVERSE_SECRET_KEY, or
from data/secret.key, made on first use and readable only by its owner. A
stolen copy of the database (or a backup of it) is then no use without the key.

Sealed values are stored as "enc:<token>"; anything without the prefix is an
older plaintext value, which unseal() still reads and seal() upgrades.
"""

import os

from cryptography.fernet import Fernet, InvalidToken

from app import accounts

PREFIX = "enc:"
_fernet: Fernet | None = None


def _box() -> Fernet:
    global _fernet
    if _fernet is None:
        key = os.environ.get("ANIVERSE_SECRET_KEY", "").strip()
        if not key:
            path = accounts.DATA_DIR / "secret.key"
            try:
                key = path.read_text().strip()
            except OSError:
                key = Fernet.generate_key().decode()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(key)
                path.chmod(0o600)
        _fernet = Fernet(key.encode())
    return _fernet


def seal(value: str | None) -> str | None:
    if value is None or value == "" or value.startswith(PREFIX):
        return value
    return PREFIX + _box().encrypt(value.encode()).decode()


def unseal(value: str | None) -> str | None:
    if not value or not value.startswith(PREFIX):
        return value  # empty, or stored before sealing existed
    try:
        return _box().decrypt(value[len(PREFIX):].encode()).decode()
    except InvalidToken:
        return None  # the key changed: as good as signed out of that service
