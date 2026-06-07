#!/bin/bash
# One-time setup for WizFlow: installs whisper.cpp and downloads the models.
set -euo pipefail

MODELS_DIR="$HOME/Library/Application Support/WizFlow/models"
HF_BASE="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
TRANSCRIBE_MODEL="ggml-large-v3-turbo-q5_0.bin"   # ~574 MB — Bangla + English transcription
TRANSLATE_MODEL="ggml-medium-q5_0.bin"            # ~539 MB — Bangla → English translation

echo "==> WizFlow setup"

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
        echo "▸ Downloading $MODEL…"
        curl -L --progress-bar -o "$MODELS_DIR/$MODEL.part" "$HF_BASE/$MODEL"
        mv "$MODELS_DIR/$MODEL.part" "$MODELS_DIR/$MODEL"
        echo "✓ $MODEL downloaded"
    fi
done

# 3. Build the app
echo "▸ Building WizFlow.app…"
bash "$(dirname "$0")/scripts/build-app.sh" release

echo ""
echo "==> Done. Next steps:"
echo "    1. open dist/WizFlow.app"
echo "    2. Grant Microphone + Accessibility permissions when prompted"
echo "    3. Hold Right Option (⌥) and speak — release to paste the transcript"
echo "    4. Hold Right Option + Shift to translate Bangla speech into English text"
