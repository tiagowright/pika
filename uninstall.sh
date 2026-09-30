#!/bin/bash
# Removes Pika: quits it, deletes /Applications/Pika.app, deletes its local
# data, and resets its privacy grants. The inverse of install.sh.
#
# The one thing a script cannot fully undo is the login item. SMAppService
# registrations live in the Background Task Management database, and the
# only command-line tool for it (sfltool resetbtm) wipes every app's
# entries, not just Pika's. So the stale row under Login Items has to be
# removed by hand; the script says so at the end.
#
# Usage: ./uninstall.sh [--keep-data] [--yes]
#   --keep-data   leave your config, recency, and learned queries in place
#   --yes         skip the confirmation prompt (for non-interactive use)
set -euo pipefail

BUNDLE_ID="io.github.tiagowright.pika"
DEST="/Applications/Pika.app"
ASSUME_YES=0
KEEP_DATA=0

usage() { echo "usage: ./uninstall.sh [--keep-data] [--yes]"; }

for arg in "$@"; do
    case "$arg" in
        --yes|-y)     ASSUME_YES=1 ;;
        --keep-data)  KEEP_DATA=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)
            echo "uninstall.sh: unknown argument '$arg'" >&2
            usage >&2
            exit 2 ;;
    esac
done

# Everything Pika writes outside its bundle (see README → Privacy). The
# icon cache is always removed: it is derived, and rebuilt on demand.
DATA_PATHS=(
    "$HOME/.config/pika"
    "$HOME/Library/Application Support/$BUNDLE_ID"
)
CACHE_PATHS=(
    "$HOME/Library/Caches/$BUNDLE_ID"
    "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
)

TO_DELETE=()
[ -e "$DEST" ] && TO_DELETE+=("$DEST")
if [ "$KEEP_DATA" -ne 1 ]; then
    for p in "${DATA_PATHS[@]}"; do [ -e "$p" ] && TO_DELETE+=("$p"); done
fi
for p in "${CACHE_PATHS[@]}"; do [ -e "$p" ] && TO_DELETE+=("$p"); done

if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will:"
    if pgrep -f "$DEST/Contents/MacOS/Pika" >/dev/null 2>&1; then
        echo "  - quit the running Pika"
    fi
    if [ "${#TO_DELETE[@]}" -gt 0 ]; then
        echo "  - DELETE:"
        for p in "${TO_DELETE[@]}"; do echo "      $p"; done
    else
        echo "  - delete nothing (no Pika files found)"
    fi
    if [ "$KEEP_DATA" -eq 1 ]; then
        echo "  - keep your config and history (--keep-data)"
    fi
    echo "  - reset Pika's Accessibility and Automation permissions"
    echo
    printf "Continue? [y/N] "
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

pkill -f "$DEST/Contents/MacOS/Pika" 2>/dev/null || true
sleep 0.3

for p in ${TO_DELETE[@]+"${TO_DELETE[@]}"}; do
    rm -rf "$p"
    echo "Removed $p"
done

# tccutil exits non-zero when there is nothing to reset; that is fine.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Reset Accessibility and Automation permissions for $BUNDLE_ID"

cat <<'DONE'

Pika is uninstalled. If you had turned on "Start at login", remove the
leftover Pika row under System Settings → General → Login Items.
DONE
