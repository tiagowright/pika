#!/bin/bash
# Builds Pika, installs it to /Applications, and launches it from there.
#
# /Applications is deliberate, not incidental: SMAppService ties a
# login-item registration to the bundle's on-disk location, so running
# Pika out of this project directory would break "start at login" the
# moment the directory moved or got cleaned up. Installing to a stable
# system location is what makes the login item durable.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
DEST="/Applications/Pika.app"

./build.sh "$CONFIG"

pkill -f "$DEST/Contents/MacOS/Pika" 2>/dev/null || true
pkill -f "$(pwd)/Pika.app/Contents/MacOS/Pika" 2>/dev/null || true
sleep 0.3

rm -rf "$DEST"
cp -R "Pika.app" "$DEST"

open "$DEST"
echo "Installed and launched $DEST ($CONFIG)"
