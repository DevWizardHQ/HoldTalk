import SwiftUI
import ServiceManagement

struct SettingsView: View {
    weak var appDelegate: AppDelegate?

    @State private var transcribeHotkey = Settings.transcribeHotkey
    @State private var translateHotkey = Settings.translateHotkey
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @StateObject private var transcribeDownloader = ModelDownloader()
    @StateObject private var translateDownloader = ModelDownloader()

    var body: some View {
        Form {
            Section("Hotkeys (hold to talk)") {
                HotkeyRecorderRow(title: "Transcribe (same language)", hotkey: $transcribeHotkey) {
                    Settings.transcribeHotkey = $0
                    appDelegate?.startHotkeyMonitor()
                }
                HotkeyRecorderRow(title: "Translate (Bangla → English)", hotkey: $translateHotkey) {
                    Settings.translateHotkey = $0
                    appDelegate?.startHotkeyMonitor()
                }
            }

            Section("Models") {
                ModelRow(
                    title: "Transcription — large-v3-turbo",
                    model: ModelManager.transcribeModel,
                    mode: .transcribe,
                    downloader: transcribeDownloader
                )
                ModelRow(
                    title: "Translation — medium",
                    model: ModelManager.translateModel,
                    mode: .translate,
                    downloader: translateDownloader
                )
                if Transcriber.findWhisperCLI() == nil {
                    Label("whisper-cli not found. Run:  brew install whisper-cpp", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hotkey recorder

private struct HotkeyRecorderRow: View {
    let title: String
    @Binding var hotkey: HotkeyConfig
    let onChange: (HotkeyConfig) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press a key…" : hotkey.displayString) {
                isRecording ? stopRecording() : startRecording()
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .red : nil)
        }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Capture a modifier key only on press (its flag is set), not release.
                let keyCode = event.keyCode
                if let flag = HotkeyConfig.modifierFlag(for: keyCode),
                   CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).contains(flag) {
                    // Required flags = other modifiers held alongside the captured key.
                    var flags = sanitized(event.modifierFlags)
                    flags.remove(flag)
                    capture(HotkeyConfig(keyCode: keyCode, requiredFlags: flags))
                }
            } else {
                capture(HotkeyConfig(keyCode: event.keyCode, requiredFlags: sanitized(event.modifierFlags)))
            }
            return nil // swallow while recording
        }
    }

    private func sanitized(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result = CGEventFlags()
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        return result
    }

    private func capture(_ config: HotkeyConfig) {
        hotkey = config
        onChange(config)
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Model row

private struct ModelRow: View {
    let title: String
    let model: ModelManager.Model
    let mode: DictationMode
    @ObservedObject var downloader: ModelDownloader

    private var installed: Bool { ModelManager.modelInstalled(for: mode) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let error = downloader.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text(model.approximateSize).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if downloader.isDownloading {
                ProgressView(value: downloader.progress)
                    .frame(width: 100)
                Button("Cancel") { downloader.cancel() }
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Download") { downloader.download(model) }
            }
        }
    }
}
