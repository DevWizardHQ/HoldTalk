# WizFlow — Push-to-Talk Dictation Tool for macOS

## Context

User wants a Wispr Flow–style dictation tool for his Mac (M1, 8GB RAM, macOS 26): hold a shortcut key → speak → release → transcribed text auto-pastes into whatever text field is focused.

Original idea was to automate ChatGPT.com's web dictation (free, no API). During brainstorming we established that ChatGPT dictation is just the Whisper model, which runs free/offline/locally via `whisper.cpp` — same quality, no browser automation fragility (bot detection, login expiry, UI changes), no account, no API, no free-tier quota. User approved the fully-local approach.

**Confirmed requirements:**
- Bangla + English speech support, accurate transcription
- Two modes: (1) transcribe — speak Bangla → Bangla text, speak English → English text (auto language detect); (2) translate — speak Bangla → English text
- Hold-to-talk: press & hold hotkey = record, release = transcribe + auto-paste into focused field
- Hotkey customizable from settings (default: Right Option = transcribe, Right Option+Shift = translate)
- Native Swift menu bar app
- **Resource-light**: user runs heavy Laravel/Node projects on 8GB RAM. Idle footprint must be ~30MB / 0% CPU. Whisper model NOT kept resident — spawn `whisper-cli` per dictation, exits after. Trade-off accepted: ~1s model-load latency per dictation.
- 100% free: no API keys, no accounts, no subscriptions

## Architecture

Single Swift app (menu bar only, no Dock icon — `LSUIElement`), project at `/Users/iqbal/Sites/wizFlow`.

```
[Global hotkey monitor (CGEventTap)] → hold detected
        ↓
[Audio recorder (AVAudioEngine)] → 16kHz mono WAV in /tmp
        ↓ on key release
[Transcriber] → spawns whisper-cli subprocess
        - transcribe mode: large-v3-turbo q5 model (~600MB on disk), language auto
        - translate mode: medium q5 model (~540MB on disk), task=translate
        ↓ stdout transcript
[Paster] → save clipboard → set transcript → synthesize Cmd+V (CGEvent) → restore clipboard
        ↓
[Menu bar UI] → icon states: idle / recording (red) / processing (spinner)
```

### Components

1. **`WizFlowApp.swift`** — SwiftUI App entry, `MenuBarExtra`, app state machine (idle → recording → processing → idle).
2. **`HotkeyMonitor.swift`** — `CGEventTap` listening for `flagsChanged`/`keyDown`/`keyUp`. Detects hold of configured key (default Right Option, keycode 61; +Shift = translate mode). Customizable: settings has a "record shortcut" capture field. Requires Accessibility permission (guide user on first run).
3. **`AudioRecorder.swift`** — `AVAudioEngine` tap, converts to 16kHz mono 16-bit PCM WAV, writes `/tmp/wizflow-<uuid>.wav`. Requires Microphone permission. Discards recordings shorter than ~0.3s (accidental taps). Engine started only while recording; fully stopped at idle.
4. **`Transcriber.swift`** — runs `Process` →
   `whisper-cli -m <model> -f <wav> -l auto --no-timestamps -np` (transcribe) or `... -l bn --translate` (translate). Parses stdout. Kills subprocess if a new dictation starts. No model stays in memory between uses.
5. **`Paster.swift`** — `NSPasteboard` save/set/restore + `CGEvent` Cmd+V synthesis. If paste fails (no Accessibility), transcript stays on clipboard and a notification tells the user.
6. **`SettingsView.swift`** — SwiftUI settings window: hotkey recorder for each mode, model status (downloaded or not, with download button), launch-at-login toggle (`SMAppService`). Stored in `UserDefaults`.
7. **`ModelManager.swift`** — checks `~/Library/Application Support/WizFlow/models/` for `ggml-large-v3-turbo-q5_0.bin` and `ggml-medium-q5_0.bin`; downloads from Hugging Face (`ggerganov/whisper.cpp` repo) with progress UI on first run.

### Dependencies

- `whisper.cpp`: install via `brew install whisper-cpp` (provides `whisper-cli`). App locates binary at `/opt/homebrew/bin/whisper-cli`, falling back to a bundled path. Setup script in repo handles brew install + first model download.
- No other third-party dependencies. Pure Swift + system frameworks.

### Error handling

- Mic/Accessibility permission missing → menu bar alert with deep-link to System Settings pane.
- whisper-cli missing/model missing → notification + settings opens to fix.
- Empty/failed transcription → brief "nothing heard" notification, no paste.
- Recording while another dictation processing → cancel old subprocess, start fresh.

## Implementation steps

1. Scaffold Xcode-buildable Swift package/project (`xcodegen` or plain `Package.swift` + manual Info.plist with `LSUIElement`, mic usage description). Git init.
2. Menu bar app shell with state machine + icon states.
3. HotkeyMonitor with CGEventTap + Accessibility permission flow; hardcode Right Option first.
4. AudioRecorder → WAV file; verify with manual playback.
5. Transcriber subprocess integration; verify Bangla + English accuracy manually with both models.
6. Paster (clipboard + Cmd+V) — test in TextEdit, VS Code, browser.
7. Settings window: customizable hotkeys, model manager UI, launch at login.
8. Setup script (`setup.sh`): brew install whisper-cpp, download models.
9. Polish: sounds on start/stop record (optional), notification feedback.

## Verification

- Build & launch: `xcodebuild` / `swift build`, app appears in menu bar.
- Hold Right Option in TextEdit, speak English → English text pastes at cursor.
- Speak Bangla → Bangla text pastes.
- Hold Right Option+Shift, speak Bangla → English translation pastes.
- Check Activity Monitor: idle RAM ≤ ~40MB, no whisper process resident after dictation.
- Change hotkey in settings → new key works, old doesn't.
- Quit/relaunch → settings persist.
