#!/bin/bash
# Builds HoldTalk.app bundle from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_DIR="dist/HoldTalk.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BINARY=".build/$CONFIG/HoldTalk"

echo "▸ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/HoldTalk"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "$APP_DIR/Contents/Resources/MenuBarIcon.png"

# Prefer a stable signing identity so macOS TCC permissions (Accessibility,
# Microphone) survive rebuilds. Falls back to ad-hoc if none exists.
# Create one with: see "Signing" in CONTRIBUTING.md
IDENTITY="${HOLDTALK_SIGN_IDENTITY:-HoldTalk Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "▸ Codesigning with identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" --identifier com.devwizardhq.holdtalk "$APP_DIR"
else
    echo "▸ Codesigning (ad-hoc — TCC permissions will reset on each rebuild)"
    codesign --force --sign - --identifier com.devwizardhq.holdtalk "$APP_DIR"
fi

echo "✓ Built $APP_DIR"
echo "  Run with: open $APP_DIR"
