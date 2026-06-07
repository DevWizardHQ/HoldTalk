# WizFlow

Push-to-talk dictation for macOS — like Wispr Flow, but 100% free and offline.

Hold a hotkey, speak (Bangla or English), release — the transcript pastes into whatever
text field is focused. Powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
running locally on your Mac. No API keys, no accounts, no subscriptions.

## Features

- **Hold-to-talk**: hold Right Option (⌥) = record, release = transcribe + auto-paste
- **Two modes**:
  - *Transcribe* — speak Bangla → Bangla text, speak English → English text (auto-detect)
  - *Translate* (Right Option + Shift) — speak Bangla → English text
- **Customizable hotkeys** from Settings
- **Resource-light**: ~30 MB idle RAM, 0% idle CPU. The Whisper model is never kept
  resident — a `whisper-cli` subprocess runs per dictation and exits. Safe to run
  alongside heavy dev workloads on 8 GB Macs.
- Menu bar app with recording/processing indicator + floating HUD

## Setup

```bash
./setup.sh
```

This installs `whisper-cpp` via Homebrew, downloads the two models (~1.1 GB total),
and builds `dist/WizFlow.app`.

Then:

1. `open dist/WizFlow.app`
2. Grant **Microphone** and **Accessibility** permissions when prompted
   (System Settings → Privacy & Security)
3. Hold **Right ⌥** and speak. Release. Text appears at your cursor.

> **Note:** the app is ad-hoc signed. After rebuilding you may need to re-grant
> Accessibility permission (remove + re-add WizFlow in System Settings).

## Models

| Mode | Model | Size | Task |
|---|---|---|---|
| Transcribe | `ggml-large-v3-turbo-q5_0` | ~574 MB | Speech → text, language auto-detected |
| Translate | `ggml-medium-q5_0` | ~539 MB | Bangla (any language) speech → English text |

Models live in `~/Library/Application Support/WizFlow/models/` and can also be
downloaded from the in-app Settings window.

## Development

```bash
swift build                  # debug build
./scripts/build-app.sh       # release .app bundle in dist/
```

## Architecture

```
HotkeyMonitor (CGEventTap, hold detection)
  → AudioRecorder (AVAudioRecorder → 16 kHz mono WAV in /tmp)
  → Transcriber (whisper-cli subprocess, exits after use)
  → Paster (clipboard swap + synthetic ⌘V, clipboard restored)
```
