#!/bin/bash
# Builds and signs Pika.app.
#
# A *stable* signature + bundle identifier across rebuilds is what lets
# the Accessibility grant survive — TCC keys off both. Do not switch
# identities or bundle IDs casually (see TECHNICAL.md §16).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
BUNDLE_ID="io.github.tiagowright.pika"
APP="Pika.app"

# Signing identity, first match wins:
#   1. $PIKA_SIGN_IDENTITY  — explicit override, for CI or a one-off build
#   2. .signing-identity    — this clone's choice, one line, gitignored
#   3. A Developer ID Application certificate in the keychain (release)
#   4. Ad-hoc — always works, but the grant resets on every rebuild
resolve_identity() {
    if [ -n "${PIKA_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$PIKA_SIGN_IDENTITY"
        return
    fi
    if [ -s .signing-identity ]; then
        local from_file
        from_file="$(head -1 .signing-identity | tr -d '\n')"
        if [ -n "$from_file" ]; then
            printf '%s' "$from_file"
            return
        fi
    fi
    local dev_id
    dev_id="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' \
        | head -1)"
    if [ -n "$dev_id" ]; then
        printf '%s' "$dev_id"
        return
    fi
    printf '%s' "-"
}

IDENTITY="$(resolve_identity)"

swift build -c "$CONFIG"

BIN=".build/$CONFIG/Pika"
RESOURCE_BUNDLE=".build/$CONFIG/Pika_Pika.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pika"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Pika</string>
    <key>CFBundleDisplayName</key><string>Pika</string>
    <key>CFBundleExecutable</key><string>Pika</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Pika reads Chrome's open tab titles so you can switch to them by name.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

if [ "$IDENTITY" = "-" ]; then
    echo "Built and signed $APP ($CONFIG) — ad-hoc"
else
    echo "Built and signed $APP ($CONFIG) — identity: $IDENTITY"
fi
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority"

if [ "$IDENTITY" = "-" ]; then
    cat >&2 <<'WARN'

warning: this build is signed ad-hoc, so its signature changes every time
  you rebuild. macOS keys the Accessibility grant off the signature, so
  Pika will silently stop raising windows after each rebuild until you
  remove and re-add it in System Settings → Privacy & Security →
  Accessibility.

  To sign with a stable identity instead, create one once in Keychain
  Access (Certificate Assistant → Create a Certificate…, Certificate
  Type: Code Signing, self-signed), then record its name either as
    echo "My Local Signing" > .signing-identity   # this clone only
  or
    export PIKA_SIGN_IDENTITY="My Local Signing"  # this shell
WARN
fi
