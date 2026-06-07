#!/bin/bash
# One-time setup for HoldTalk: installs whisper.cpp and downloads the models.
set -euo pipefail

MODELS_DIR="$HOME/Library/Application Support/HoldTalk/models"
HF_BASE="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
TRANSCRIBE_MODEL="ggml-large-v3-turbo-q5_0.bin"   # ~574 MB — Bangla + English transcription
TRANSLATE_MODEL="ggml-medium-q5_0.bin"            # ~539 MB — Bangla → English translation

echo "==> HoldTalk setup"

# 1. whisper.cpp
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

# 3. Build the app
echo "▸ Building HoldTalk.app…"
bash "$(dirname "$0")/scripts/build-app.sh" release

# 4. Install into /Applications
echo "▸ Installing to /Applications/HoldTalk.app…"
osascript -e 'tell application "HoldTalk" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/HoldTalk.app
cp -R "$(dirname "$0")/dist/HoldTalk.app" /Applications/HoldTalk.app

echo ""
echo "==> Done. Next steps:"
echo "    1. open /Applications/HoldTalk.app   (also in Launchpad/Spotlight)"
echo "    2. Grant Microphone + Accessibility permissions when prompted"
echo "    3. Hold Right Option (⌥) and speak — release to paste the transcript"
echo "    4. Hold Right Option + Shift to translate Bangla speech into English text"
