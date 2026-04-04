import hashlib
import time

def generate_token(id_val: str, secret: str, tolerance: int = 5) -> str:
    """
    Replicates JS token generation (e.g., md5(id + secret + timestamp)).
    Using a window of `tolerance` seconds to match server time.
    """
    # For a real implementation, you might need to try a few timestamps around the current time
    # to account for client-server time drift.
    ts = int(time.time())
    raw = f"{id_val}{secret}{ts}"
    return hashlib.md5(raw.encode()).hexdigest()
