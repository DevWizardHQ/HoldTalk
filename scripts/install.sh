#!/bin/bash
# HoldTalk installer — prebuilt app, no Xcode required.
#
#   curl -fsSL https://raw.githubusercontent.com/DevWizardHQ/HoldTalk/main/scripts/install.sh | bash
#
# Installs: whisper-cpp (Homebrew), the two Whisper models (~1.1 GB),
# and the latest HoldTalk release into /Applications.
set -euo pipefail

REPO="DevWizardHQ/HoldTalk"
MODELS_DIR="$HOME/Library/Application Support/HoldTalk/models"
HF_BASE="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
TRANSCRIBE_MODEL="ggml-large-v3-turbo-q5_0.bin"   # ~574 MB — multilingual transcription
TRANSLATE_MODEL="ggml-medium-q5_0.bin"            # ~539 MB — any language → English

echo "==> HoldTalk installer"

# 1. Homebrew + whisper.cpp
if ! command -v brew >/dev/null 2>&1; then
    echo "✗ Homebrew is required (https://brew.sh) — install it and re-run."
    exit 1
fi
if command -v whisper-cli >/dev/null 2>&1; then
    echo "✓ whisper-cli already installed"
else
    echo "▸ Installing whisper.cpp via Homebrew…"
    brew install whisper-cpp
fi

# 2. Models
mkdir -p "$MODELS_DIR"
for MODEL in "$TRANSCRIBE_MODEL" "$TRANSLATE_MODEL"; do
    if [ -f "$MODELS_DIR/$MODEL" ]; then
        echo "✓ $MODEL already downloaded"
    else
        echo "▸ Downloading ${MODEL}…"
        curl -L --progress-bar -o "$MODELS_DIR/$MODEL.part" "$HF_BASE/$MODEL"
        mv "$MODELS_DIR/$MODEL.part" "$MODELS_DIR/$MODEL"
        echo "✓ $MODEL downloaded"
    fi
done

# 3. Latest prebuilt release
echo "▸ Fetching latest release…"
API_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
ZIP_URL="$(printf '%s' "$API_JSON" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
SHA_URL="$(printf '%s' "$API_JSON" | grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
if [ -z "$ZIP_URL" ]; then
    echo "✗ Could not find a release download. Check https://github.com/$REPO/releases"
    exit 1
fi

WORK="$(mktemp -d /tmp/holdtalk-install.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
echo "▸ Downloading $(basename "$ZIP_URL")…"
curl -fL --progress-bar -o "$WORK/HoldTalk.zip" "$ZIP_URL"

# 4. Verify checksum when published
if [ -n "$SHA_URL" ]; then
    echo "▸ Verifying checksum…"
    EXPECTED="$(curl -fsSL "$SHA_URL" | awk '{print $1}')"
    ACTUAL="$(shasum -a 256 "$WORK/HoldTalk.zip" | awk '{print $1}')"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "✗ Checksum mismatch — aborting."
        exit 1
    fi
    echo "✓ Checksum OK"
fi

# 5. Install into /Applications
echo "▸ Installing to /Applications/HoldTalk.app…"
ditto -x -k "$WORK/HoldTalk.zip" "$WORK/unpacked"
APP_PATH="$(find "$WORK/unpacked" -maxdepth 1 -name '*.app' | head -1)"
if [ -z "$APP_PATH" ]; then
    echo "✗ Archive did not contain an app."
    exit 1
fi
osascript -e 'tell application "HoldTalk" to quit' >/dev/null 2>&1 || true
pkill -x HoldTalk 2>/dev/null || true
rm -rf /Applications/HoldTalk.app
mv "$APP_PATH" /Applications/HoldTalk.app
# Clear quarantine so the first launch isn't blocked (the app is open source
# and was checksum-verified above; it is not notarized by Apple).
xattr -dr com.apple.quarantine /Applications/HoldTalk.app 2>/dev/null || true

echo ""
echo "==> Done. Next steps:"
echo "    1. open /Applications/HoldTalk.app   (also in Launchpad/Spotlight)"
echo "    2. Grant Microphone + Accessibility permissions when prompted"
echo "    3. Hold Right Option (⌥) and speak — release to paste the transcript"
echo "    4. Double-tap Right Option for hands-free; tap once to stop"

open /Applications/HoldTalk.app 2>/dev/null || true
