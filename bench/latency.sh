#!/bin/bash
# Measures the latencies in the README's "Blazing fast" table.
#
# Relaunches the installed Pika with its latency probe on
# (PIKA_LATENCY_LOG, see LatencyProbe.swift), drives it with synthetic key
# events, prints mean and percentiles per interaction, then relaunches Pika
# normally. It takes over the keyboard while it runs, and Enter switches
# windows, so leave the machine alone until it finishes.
#
# Usage: bench/latency.sh [rounds]     (default 200; each round is ~1.5 s)
#
# Needs a Pika built with the probe installed in /Applications
# (./install.sh), and Accessibility for this terminal so it can post keys.
set -euo pipefail
cd "$(dirname "$0")"

ROUNDS="${1:-200}"
APP="/Applications/Pika.app"
WORK="$(mktemp -d)"
LOG="$WORK/latency.tsv"

[ -d "$APP" ] || { echo "latency.sh: $APP not found — run ./install.sh first" >&2; exit 1; }

swiftc -O -o "$WORK/driver" driver.swift

relaunch_normally() {
    pkill -f "$APP/Contents/MacOS/Pika" 2>/dev/null || true
    sleep 0.5
    open "$APP"
    rm -rf "$WORK"
}
trap relaunch_normally EXIT

pkill -f "$APP/Contents/MacOS/Pika" 2>/dev/null || true
sleep 0.5
open --env "PIKA_LATENCY_LOG=$LOG" "$APP"
sleep 3 # first window sweep and panel prewarm

echo "$(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), $ROUNDS rounds"
"$WORK/driver" "$LOG" "$ROUNDS"
