#!/usr/bin/env bash
# Copy the original app's artwork, bundled fonts, and their licenses.
# No generated lookalikes: both Rust looks use the exact Flutter source assets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/aniverse_mobile_rust/assets"
SRC="$ROOT/aniverse_mobile/assets"
mkdir -p "$DEST/icon" "$DEST/fonts/manga" "$DEST/manga"
for asset in aniverse_icon.png aniverse_icon_pixel.png; do
  cp "$SRC/icon/$asset" "$DEST/icon/$asset"
done
for asset in PressStart2P-Regular.ttf DotGothic16-Regular.ttf OFL-PressStart2P.txt OFL-DotGothic16.txt; do
  cp "$SRC/fonts/$asset" "$DEST/fonts/$asset"
done
cp "$SRC/fonts/manga/"* "$DEST/fonts/manga/"
cp "$SRC/manga/"*.png "$DEST/manga/"
printf 'Copied original Manga/Pixel artwork and licensed fonts to %s\n' "$DEST"
