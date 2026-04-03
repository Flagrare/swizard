#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/Assets"
BASE_PNG="$ASSETS_DIR/AppIcon-1024.png"
ICONSET_DIR="$ASSETS_DIR/SWizard.iconset"
ICNS_FILE="$ASSETS_DIR/SWizard.icns"

mkdir -p "$ASSETS_DIR"

magick -size 1024x1024 canvas:none \
  -fill "#0b1220" -draw "roundrectangle 56,56 968,968 220,220" \
  \( -size 1024x1024 radial-gradient:'#1e3a8a-#0b1220' -alpha set -channel A -evaluate set 55% +channel \) -compose over -composite \
  -fill "#38bdf8" -draw "roundrectangle 180,220 844,820 160,160" \
  -fill "#082f49" -draw "polygon 512,250 660,670 364,670" \
  -fill "#f8fafc" -draw "polygon 512,300 625,625 399,625" \
  -fill "#f59e0b" -draw "polygon 512,470 536,525 594,530 550,570 564,626 512,594 460,626 474,570 430,530 488,525" \
  "$BASE_PNG"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
rm -rf "$ICONSET_DIR"

echo "Generated icon at $ICNS_FILE"
