#!/bin/bash
# Builds Pika.app and signs it with the local "Winby Local Signing"
# identity. A *stable* signature + bundle identifier across rebuilds is
# what lets the Accessibility grant survive — TCC keys off both. Do not
# switch identities or bundle IDs casually (see TECHNICAL.md §16).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
IDENTITY="Winby Local Signing"
BUNDLE_ID="dev.pika.app"
APP="Pika.app"

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
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Pika reads Chrome's open tab titles so you can switch to them by name.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
echo "Built and signed $APP ($CONFIG)"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority"
