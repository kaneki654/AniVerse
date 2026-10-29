"""Render the manga UI's assets (aniverse_mobile/lib/ui_manga):

- The AniVerse emblem inked like a manga page, from assets/icon/aniverse_icon.png:
  the same "A", orbit and play mark, drawn as black ink lines (the outline and
  the edges between the emblem's facets), screentone dots for its shadows and
  a flat red fill. Each is its own layer, so the intro can ink the logo in
  stage by stage: assets/manga/logo_lines.png, logo_tone.png, logo_color.png,
  and logo.png with all three on a paper-white halo.
- The fonts, from the system's font packages (licences copied alongside):
  Lato Black for titles, Roboto Condensed for text, and Noto Sans CJK JP Bold
  cut down to the kana and the few kanji the sound effects use (the whole font
  is 20 MB; the cut is a few hundred KB).

    venv/bin/python scripts/make_manga_assets.py
"""

import shutil
from pathlib import Path

import numpy as np
from fontTools import subset
from fontTools.ttLib import TTCollection
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "aniverse_mobile"
ICON = APP / "assets" / "icon" / "aniverse_icon.png"
OUT = APP / "assets" / "manga"
FONTS = APP / "assets" / "fonts" / "manga"

SIZE = 640  # the emblem's layers, square
INK = (12, 10, 10)
RED = (229, 9, 20)
RED_LIGHT = (255, 90, 100)

# What the sound effects and captions say (lib/ui_manga), beyond the kana.
KANJI = "読込中次回完終了新着話漫画開始音撃熱血一時停止再生見逃探検索保存予定"


def _layers() -> None:
    img = Image.open(ICON).convert("RGBA")
    box = img.getchannel("A").point([0] * 41 + [255] * 215).getbbox()  # alpha above 40
    img = img.crop(box)
    side = int(max(img.size) * 1.12)  # room for the outline and halo
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    img = square.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    a = np.asarray(img).astype(np.float32) / 255
    mask = a[..., 3] > 0.5
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    inside = lum[mask]
    lo, hi = np.percentile(inside, 3), np.percentile(inside, 97)
    shade = np.clip((lum - lo) / max(hi - lo, 1e-6), 0, 1)  # 0 = darkest facet

    def grow(m: np.ndarray, px: int) -> np.ndarray:
        im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(2 * px + 1))
        return np.asarray(im) > 127

    # Ink lines: the outline round the emblem (and its holes), and the edges
    # between its facets, where the shading jumps.
    soft = np.asarray(Image.fromarray((shade * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)),
                      dtype=np.float32) / 255
    gy, gx = np.gradient(soft)
    edge = np.hypot(gx, gy) * mask
    facets = edge > np.percentile(edge[mask], 90)
    facets = grow(facets, 1) & grow(mask, 0)
    outline = grow(mask, 7) & ~mask
    lines = outline | facets

    # Screentone: dots on a 45-degree grid, bigger where the facet is darker;
    # the darkest corners go solid.
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    step = 7.0
    u = (xx + yy) / np.sqrt(2) / step
    v = (xx - yy) / np.sqrt(2) / step
    dist = np.hypot(u - np.round(u), v - np.round(v)) * step  # to the nearest dot centre
    dark = np.clip((0.5 - shade) / 0.5, 0, 1)
    radius = dark * step * 0.62
    tone = mask & ((dist < radius) | (shade < 0.1)) & ~lines

    def save(name: str, on: np.ndarray, rgb) -> np.ndarray:
        out = np.zeros((SIZE, SIZE, 4), np.uint8)
        out[on] = (*rgb, 255)
        Image.fromarray(out, "RGBA").save(OUT / name, optimize=True)
        return out

    color = np.zeros((SIZE, SIZE, 4), np.uint8)
    color[mask] = (*RED, 255)
    color[mask & (shade > 0.78)] = (*RED_LIGHT, 255)
    Image.fromarray(color, "RGBA").save(OUT / "logo_color.png", optimize=True)
    tone_px = save("logo_tone.png", tone, INK)
    line_px = save("logo_lines.png", lines, INK)

    # All of it on a paper halo, so the emblem reads on dark screens too.
    full = np.zeros((SIZE, SIZE, 4), np.uint8)
    full[grow(mask, 13)] = (250, 246, 236, 255)
    for layer in (color, tone_px, line_px):
        on = layer[..., 3] > 0
        full[on] = layer[on]
    Image.fromarray(full, "RGBA").save(OUT / "logo.png", optimize=True)


def _fonts() -> None:
    FONTS.mkdir(parents=True, exist_ok=True)
    shutil.copy("/usr/share/fonts/truetype/lato/Lato-Black.ttf", FONTS / "Lato-Black.ttf")
    for w in ("Regular", "Bold"):
        shutil.copy(f"/usr/share/fonts/truetype/roboto/unhinted/RobotoCondensed-{w}.ttf",
                    FONTS / f"RobotoCondensed-{w}.ttf")
    for pkg, name in (("fonts-lato", "Lato"), ("fonts-roboto-unhinted", "RobotoCondensed"),
                      ("fonts-noto-cjk", "NotoSansCJK")):
        shutil.copy(f"/usr/share/doc/{pkg}/copyright", FONTS / f"LICENSE-{name}.txt")

    collection = TTCollection("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc")
    jp = next(f for f in collection.fonts if "JP" in f["name"].getDebugName(1))
    chars = {*range(0x20, 0x7F), *range(0x3000, 0x3040), *range(0x3040, 0x30A0), *range(0x30A0, 0x3100),
             *range(0xFF01, 0xFF5F), *(ord(c) for c in KANJI), 0x2026, 0x2014, 0x2665}
    opts = subset.Options()
    opts.hinting = False
    opts.desubroutinize = True
    opts.layout_features = ["kern", "palt", "vert", "vrt2"]
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=chars)
    sub.subset(jp)
    jp.save(FONTS / "MangaSfx-Bold.otf")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    _layers()
    _fonts()
    for p in sorted([*OUT.iterdir(), *FONTS.iterdir()]):
        print(f"{p.relative_to(APP)}  {p.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
