#!/bin/bash
# Builds WizFlow.app bundle from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_DIR="dist/WizFlow.app"

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"

BINARY=".build/$CONFIG/WizFlow"

echo "▸ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/WizFlow"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

echo "▸ Codesigning (ad-hoc)"
codesign --force --sign - --identifier com.iqbal.wizflow "$APP_DIR"

echo "✓ Built $APP_DIR"
echo "  Run with: open $APP_DIR"
