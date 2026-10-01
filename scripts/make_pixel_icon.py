"""Build the pixel-art AniVerse logo from the original emblem.

    python3 scripts/make_pixel_icon.py

Reads aniverse_mobile/assets/icon/aniverse_icon.png (the smooth logo, left
untouched) and writes:

  assets/icon/aniverse_icon_pixel.png        the logo at 1 art pixel per pixel,
                                             drawn in-app with no smoothing
  assets/icon/aniverse_icon_pixel_1024.png   a 1024px preview of it
  android res ic_launcher_pixel*             the launcher icon at every density

The launcher icon gets its own resource name (ic_launcher_pixel) instead of
being generated over ic_launcher, so the classic icon stays exactly as it was;
AndroidManifest.xml picks which one the app uses.
"""
from collections import Counter
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "aniverse_mobile"
SOURCE = ROOT / "assets/icon/aniverse_icon.png"
RES = ROOT / "android/app/src/main/res"

# Art width in pixels, before the outline. 32 keeps the play triangle inside
# the A readable; much below that it disappears.
GRID = 32

# The 2D UI's blood palette, darkest to lightest, and its outline black.
RAMP = [(0x3D, 0x01, 0x07), (0x7A, 0x04, 0x10), (0xB8, 0x08, 0x16),
        (0xE5, 0x09, 0x14), (0xFF, 0x5A, 0x64)]
OUTLINE = (0x05, 0x03, 0x05)

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def pixelate() -> Image.Image:
    src = Image.open(SOURCE).convert("RGBA")
    src = src.crop(src.getchannel("A").point([255 if v > 20 else 0 for v in range(256)]).getbbox())
    w, h = GRID, round(GRID * src.height / src.width)
    small = src.resize((w, h), Image.Resampling.BOX)

    def rgba(x: int, y: int) -> tuple[int, ...]:
        p = small.getpixel((x, y))
        if not isinstance(p, tuple):  # an RGBA image's pixels are 4-tuples
            raise TypeError(f"expected an RGBA pixel, got {p!r}")
        return p

    def shade(rgb):
        return min(range(len(RAMP)),
                   key=lambda i: sum((a - b) ** 2 for a, b in zip(RAMP[i], rgb)))

    # Hard edges: a pixel is either logo or clear, never half-transparent.
    grid = [[shade(rgba(x, y)[:3]) if rgba(x, y)[3] >= 128 else None
             for x in range(w)] for y in range(h)]

    # A shade none of its four neighbours share is downsampling noise, not
    # shading; it takes the most common neighbouring shade instead.
    for _ in range(2):
        cleaned = [row[:] for row in grid]
        for y in range(h):
            for x in range(w):
                if grid[y][x] is None:
                    continue
                around = [grid[y + dy][x + dx] for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0))
                          if 0 <= y + dy < h and 0 <= x + dx < w and grid[y + dy][x + dx] is not None]
                if around and grid[y][x] not in around:
                    cleaned[y][x] = Counter(around).most_common(1)[0][0]
        grid = cleaned

    art = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            level = grid[y][x]
            if level is not None:
                art.putpixel((x + 1, y + 1), RAMP[level] + (255,))

    # One-pixel outline round the whole shape, as sprites are drawn.
    alpha = art.getchannel("A")
    for y in range(art.height):
        for x in range(art.width):
            if alpha.getpixel((x, y)) == 0 and any(
                    0 <= x + dx < art.width and 0 <= y + dy < art.height
                    and alpha.getpixel((x + dx, y + dy)) == 255
                    for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0))):
                art.putpixel((x, y), OUTLINE + (255,))
    return art


def placed(art: Image.Image, canvas: int, target: float) -> Image.Image:
    """[art] centred on a clear square canvas, scaled by a whole number so
    every art pixel is the same size, as close to [target] wide as that allows."""
    k = max(1, int(target // art.width))
    big = art.resize((art.width * k, art.height * k), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.alpha_composite(big, ((canvas - big.width) // 2, (canvas - big.height) // 2))
    return out


def main():
    art = pixelate()
    art.save(ROOT / "assets/icon/aniverse_icon_pixel.png")
    placed(art, 1024, 1024 * 0.8).save(ROOT / "assets/icon/aniverse_icon_pixel_1024.png")

    for name, d in DENSITIES.items():
        # Adaptive foreground: a 108dp layer whose middle 66dp is always shown.
        # The emblem is sized to about 56dp, like the smooth logo it replaces.
        fg = RES / f"drawable-{name}"
        fg.mkdir(exist_ok=True)
        placed(art, round(108 * d), 58 * d).save(fg / "ic_launcher_pixel_foreground.png")
        # Legacy icon, for launchers older than Android 8.
        legacy = RES / f"mipmap-{name}"
        legacy.mkdir(exist_ok=True)
        placed(art, round(48 * d), 46 * d).save(legacy / "ic_launcher_pixel.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher_pixel.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@color/ic_launcher_background"/>\n'
        '  <foreground android:drawable="@drawable/ic_launcher_pixel_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    print(f"pixel logo {art.width}x{art.height} written; launcher icon ic_launcher_pixel at "
          + ", ".join(DENSITIES))


if __name__ == "__main__":
    main()
