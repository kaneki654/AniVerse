import time
from typing import Any, Dict, Optional

class SimpleCache:
    """
    A simple in-memory cache with TTL. 
    In production, this should be swapped with a Redis integration.
    """
    def __init__(self):
        self._store: Dict[str, Dict[str, Any]] = {}

    def get(self, key: str) -> Optional[Any]:
        if key in self._store:
            item = self._store[key]
            if time.time() < item["expires_at"]:
                return item["value"]
            else:
                del self._store[key]
        return None

    def set(self, key: str, value: Any, ttl_seconds: int = 3600):
        self._store[key] = {
            "value": value,
            "expires_at": time.time() + ttl_seconds
        }

    def cleanup(self):
        """Remove all expired keys."""
        now = time.time()
        expired_keys = [k for k, v in self._store.items() if v["expires_at"] < now]
        for k in expired_keys:
            del self._store[k]

cache = SimpleCache()
