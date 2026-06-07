# Contributing to WizFlow

Thanks for your interest in improving WizFlow!

## Development setup

```bash
git clone https://github.com/<you>/wizFlow.git
cd wizFlow
./setup.sh            # installs whisper-cpp + models, builds the app
swift build           # debug build during development
./scripts/build-app.sh  # release .app bundle in dist/
```

Requirements: macOS 14+, Xcode command line tools, Homebrew.

> **Note:** the app is ad-hoc signed, so after each rebuild you may need to
> re-grant Accessibility permission (System Settings → Privacy & Security).

## Project layout

| Path | Purpose |
|---|---|
| `Sources/WizFlow/AppDelegate.swift` | App lifecycle, dictation state machine |
| `Sources/WizFlow/HotkeyMonitor.swift` | Global hold-to-talk hotkey (CGEventTap) |
| `Sources/WizFlow/AudioRecorder.swift` | Mic → 16 kHz mono WAV |
| `Sources/WizFlow/WhisperServerManager.swift` | Keep-warm whisper-server lifecycle |
| `Sources/WizFlow/Transcriber.swift` | HTTP inference + whisper-cli fallback |
| `Sources/WizFlow/Paster.swift` | Clipboard swap + synthetic ⌘V |
| `Sources/WizFlow/SettingsView.swift` | Settings UI |
| `Sources/WizFlow/ModelManager.swift` | Model files + in-app downloads |

## Guidelines

- Keep the idle footprint near zero — no resident models, no polling loops.
- Pure Swift + system frameworks only; avoid adding dependencies.
- Test both dictation modes (transcribe + translate) and at least Bangla + English
  before opening a PR.
- One focused change per PR with a clear description.

## Reporting issues

Include: macOS version, chip (M1/M2/…), RAM, `whisper-cli --version` output,
and steps to reproduce. For transcription quality issues, attach the language
spoken and (if possible) a short sample WAV.
