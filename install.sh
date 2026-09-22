#!/bin/bash
# Builds Pika, installs it to /Applications, and launches it from there.
#
# /Applications is deliberate, not incidental: SMAppService ties a
# login-item registration to the bundle's on-disk location, so running
# Pika out of this project directory would break "start at login" the
# moment the directory moved or got cleaned up. Installing to a stable
# system location is what makes the login item durable.
#
# Usage: ./install.sh [debug|release] [--yes]
#   --yes   skip the confirmation prompt (for non-interactive use)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        --yes|-y)        ASSUME_YES=1 ;;
        debug|release)   CONFIG="$arg" ;;
        -h|--help)
            echo "usage: ./install.sh [debug|release] [--yes]"
            exit 0 ;;
        *)
            echo "install.sh: unknown argument '$arg'" >&2
            echo "usage: ./install.sh [debug|release] [--yes]" >&2
            exit 2 ;;
    esac
done

DEST="/Applications/Pika.app"

# This script quits a running Pika and replaces a directory under
# /Applications. Both are reasonable things to want spelled out before
# they happen, so say so and ask — unless told not to.
if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will:"
    echo "  1. build Pika ($CONFIG)"
    if pgrep -f "$DEST/Contents/MacOS/Pika" >/dev/null 2>&1; then
        echo "  2. quit the running Pika"
    else
        echo "  2. quit Pika, if it is running"
    fi
    if [ -e "$DEST" ]; then
        echo "  3. DELETE the existing $DEST and replace it"
    else
        echo "  3. install it to $DEST"
    fi
    echo "  4. launch it from there"
    echo
    printf "Continue? [y/N] "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

./build.sh "$CONFIG"

pkill -f "$DEST/Contents/MacOS/Pika" 2>/dev/null || true
pkill -f "$(pwd)/Pika.app/Contents/MacOS/Pika" 2>/dev/null || true
sleep 0.3

rm -rf "$DEST"
cp -R "Pika.app" "$DEST"

# Leaving the build output in place would mean two bundles on the machine
# claiming the same CFBundleIdentifier. macOS resolves an identifier back
# to a path through Launch Services to draw the Privacy & Security rows, so
# a second candidate makes Pika impossible to add to Accessibility: the row
# just never appears. Delete the intermediate now that it is installed.
rm -rf "Pika.app"

open "$DEST"
echo "Installed and launched $DEST ($CONFIG)"
