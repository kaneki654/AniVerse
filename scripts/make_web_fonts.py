"""Build the pixel website's fonts from the app's bundled TTFs.

    python3 -m pip install fonttools brotli
    python3 scripts/make_web_fonts.py

Reads aniverse_mobile/assets/fonts and writes WOFF2 files to
app/static/pixel/fonts. DotGothic16 is 2 MB because it covers Japanese, which
is far too much to download on every page for text that is almost all Latin,
so it is split in two: a small Latin file that every page loads, and the rest,
which the browser fetches only when a page actually shows Japanese (the CSS
gives each file a unicode-range). Only needed again if the fonts change.
"""
import shutil
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "aniverse_mobile/assets/fonts"
OUT = ROOT / "app/static/pixel/fonts"

# Basic Latin, Latin-1, Latin Extended-A (romaji macrons: ō, ū), punctuation,
# arrows, and the few symbols titles use. Must match LATIN_RANGE in pixel.css.
LATIN = ("U+0000-017F,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,"
         "U+20AC,U+2122,U+2190-2199,U+2212,U+2215,U+FEFF,U+FFFD")


def _ranges(spec: str) -> list[int]:
    codes: list[int] = []
    for part in spec.split(","):
        lo, _, hi = part.removeprefix("U+").partition("-")
        codes.extend(range(int(lo, 16), int(hi or lo, 16) + 1))
    return codes


def build(src: Path, out: Path, unicodes: list[int]) -> None:
    font = TTFont(src)
    options = subset.Options(flavor="woff2", layout_features=["*"], name_IDs=["*"], notdef_outline=True)
    sub = subset.Subsetter(options)
    sub.populate(unicodes=unicodes)
    sub.subset(font)
    font.flavor = "woff2"
    font.save(out)
    print(f"{out.relative_to(ROOT)}: {out.stat().st_size // 1024} KB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    latin = _ranges(LATIN)

    build(SRC / "PressStart2P-Regular.ttf", OUT / "PressStart2P-latin.woff2", latin)

    dot = SRC / "DotGothic16-Regular.ttf"
    build(dot, OUT / "DotGothic16-latin.woff2", latin)
    cmap = TTFont(dot).getBestCmap() or {}
    rest = sorted(set(cmap) - set(latin))
    build(dot, OUT / "DotGothic16-cjk.woff2", rest)

    for name in ("OFL-PressStart2P.txt", "OFL-DotGothic16.txt"):
        shutil.copy(SRC / name, OUT / name)


if __name__ == "__main__":
    main()
