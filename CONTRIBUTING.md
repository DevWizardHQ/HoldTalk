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

## Signing

macOS ties Accessibility/Microphone permissions to the app's code signature.
Ad-hoc signatures change on every build, forcing you to re-grant permissions.
Create a stable local signing certificate once and the build script picks it
up automatically:

```bash
cd /tmp
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
  -subj "/CN=WizFlow Dev" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -out w.p12 -inkey k.pem -in c.pem -name "WizFlow Dev" -passout pass:x
security import w.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db c.pem
rm k.pem c.pem w.p12
```

Use a different identity name via `WIZFLOW_SIGN_IDENTITY=<name> ./scripts/build-app.sh`.

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
