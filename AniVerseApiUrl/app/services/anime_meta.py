"""Re-export of the repo-root ``anime_meta`` module.

The metadata layer is shared by both processes -- the frontend at the repo root
and this backend package -- but they both have a top-level package called
``app``, so the frontend cannot simply put this directory on sys.path and
import it. Loading the single canonical file by path sidesteps that and keeps
one copy: two would drift, and this is the code that decides whether the whole
app survives an AniList outage.
"""

import importlib.util as _util
import os as _os
import sys as _sys

_ROOT = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(
    _os.path.abspath(__file__)))))
_PATH = _os.path.join(_ROOT, "anime_meta.py")

_spec = _util.spec_from_file_location("aniverse_anime_meta", _PATH)
if _spec is None or _spec.loader is None:  # pragma: no cover
    raise ImportError("cannot load the shared metadata layer from %s" % _PATH)

_module = _util.module_from_spec(_spec)
# Registered under its own name so the frontend and backend share one instance,
# and with it one circuit breaker and one set of caches.
_sys.modules.setdefault("aniverse_anime_meta", _module)
_spec.loader.exec_module(_module)

globals().update({k: v for k, v in vars(_module).items() if not k.startswith("__")})
