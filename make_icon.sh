#!/bin/bash
# Regenerates AppIcon.icns from AppIcon.svg. Re-run this after editing
# the SVG, then re-run build.sh/install.sh to pick up the new icon.
set -euo pipefail
cd "$(dirname "$0")"

SVG="AppIcon.svg"
ICONSET="AppIcon.iconset"
PNG_SRC="/tmp/pika_icon_src.png"

qlmanage -t -s 1024 -o /tmp "$SVG" >/dev/null
mv "/tmp/$(basename "$SVG").png" "$PNG_SRC"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16     "$PNG_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$PNG_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$PNG_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$PNG_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$PNG_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$PNG_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$PNG_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$PNG_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$PNG_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$PNG_SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "Regenerated AppIcon.icns from $SVG"
