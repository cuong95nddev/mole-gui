#!/bin/sh
# Makes Resources/AppIcon.icns from Resources/icon.svg, shrunk onto macOS's
# icon grid (body 824 of 1024 px, centred). Same style as Tern/Gannet:
# black tile, white geometric art, one yellow accent.
#   needs rsvg-convert (brew install librsvg) and iconutil (macOS)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SVG="$ROOT/Resources/icon.svg"
OUT="$ROOT/Resources/AppIcon.icns"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
inner=$(sed -e '1d' -e '$d' "$SVG")
cat > "$STAGE/icon.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <g transform="translate(18.13 18.13) scale(0.8583)">
$inner
  </g>
</svg>
SVG

set_dir="$STAGE/AppIcon.iconset"
mkdir "$set_dir"
for size in 16 32 128 256 512; do
    rsvg-convert -w $size -h $size "$STAGE/icon.svg" -o "$set_dir/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) "$STAGE/icon.svg" -o "$set_dir/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$set_dir" -o "$OUT"
echo "$OUT"
