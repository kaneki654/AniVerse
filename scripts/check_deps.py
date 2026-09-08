"""Print the pip names of any packages the two servers need but cannot import.

Prints nothing and exits 0 when everything is present, so callers can test the
output rather than the exit code. Shared by start_all.sh and start_all.bat so
the list of required packages exists in exactly one place.

The module name and the pip name differ often enough to matter here: Crypto
comes from pycryptodome and py_mini_racer from mini-racer, and reporting the
import name would send you looking for a package that does not exist.
"""
import importlib.util
import sys

REQUIRED = [
    # (import name, pip name)
    ("fastapi", "fastapi"),
    ("uvicorn", "uvicorn"),
    ("httpx", "httpx"),
    ("jinja2", "jinja2"),
    ("Crypto", "pycryptodome"),
    ("numpy", "numpy"),
    ("rapidfuzz", "rapidfuzz"),
    ("selectolax", "selectolax"),
    ("m3u8", "m3u8"),
    ("apscheduler", "APScheduler"),
    ("py_mini_racer", "mini-racer"),
]


def main():
    missing = []
    for module, package in REQUIRED:
        try:
            found = importlib.util.find_spec(module) is not None
        except (ImportError, ValueError):
            found = False
        if not found:
            missing.append(package)
    if missing:
        sys.stdout.write(" ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
