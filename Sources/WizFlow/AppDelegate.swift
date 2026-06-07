import AppKit
import AVFoundation
import SwiftUI

enum DictationMode: String {
    case transcribe
    case translate
}

enum AppPhase {
    case idle
    case recording(DictationMode)
    case processing(DictationMode)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private var hotkeyMonitor: HotkeyMonitor?
    private let hud = HUDController()
    private var settingsWindow: NSWindow?
    private var accessibilityPollTimer: Timer?

    private(set) var phase: AppPhase = .idle {
        didSet { updateStatusIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("launch: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        setupStatusItem()
        requestMicrophoneAccess()

        if !AXIsProcessTrusted() {
            promptForAccessibility()
        }
        // Always poll: AXIsProcessTrusted can report a stale grant (old signature)
        // while the event tap still fails. Keep trying until the tap installs.
        startHotkeyMonitorWithRetry()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WhisperServerManager.shared.shutdownAll()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()
        let holdInfo = NSMenuItem(title: "Hold hotkey to dictate", action: nil, keyEquivalent: "")
        holdInfo.isEnabled = false
        menu.addItem(holdInfo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WizFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private static let logoIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false // full-color logo
        return image
    }()

    private func updateStatusIcon() {
        switch phase {
        case .idle:
            if let logo = Self.logoIcon {
                statusItem.button?.image = logo
                statusItem.button?.contentTintColor = nil
                return
            }
            setSymbolIcon("mic", description: "WizFlow idle", tint: nil)
        case .recording:
            setSymbolIcon("mic.fill", description: "WizFlow recording", tint: .systemRed)
        case .processing:
            setSymbolIcon("waveform", description: "WizFlow processing", tint: nil)
        }
    }

    private func setSymbolIcon(_ symbolName: String, description: String, tint: NSColor?) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = tint
    }

    // MARK: - Permissions

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showAlert(
                        title: "Microphone access needed",
                        text: "Enable WizFlow in System Settings → Privacy & Security → Microphone, then relaunch."
                    )
                }
            }
        }
    }

    /// Triggers the system Accessibility prompt and opens the settings pane.
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Tries to install the event tap; on failure retries every 2s until it
    /// succeeds (e.g. the user grants Accessibility while we wait). No relaunch needed.
    private func startHotkeyMonitorWithRetry() {
        accessibilityPollTimer?.invalidate()
        if startHotkeyMonitorOnce() {
            Log.write("hotkey: event tap installed")
            return
        }
        Log.write("hotkey: event tap failed, polling for Accessibility grant")
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.startHotkeyMonitorOnce() else { return }
            timer.invalidate()
            self.accessibilityPollTimer = nil
            Log.write("hotkey: event tap installed after grant")
            NSSound(named: "Glass")?.play() // audible "ready" cue
        }
    }

    // MARK: - Hotkey

    /// Called from Settings when a hotkey changes.
    func startHotkeyMonitor() {
        if !startHotkeyMonitorOnce() {
            startHotkeyMonitorWithRetry()
        }
    }

    @discardableResult
    private func startHotkeyMonitorOnce() -> Bool {
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        let monitor = HotkeyMonitor(
            transcribeHotkey: Settings.transcribeHotkey,
            translateHotkey: Settings.translateHotkey
        )
        monitor.onHoldStart = { [weak self] mode in self?.beginDictation(mode: mode) }
        monitor.onHoldEnd = { [weak self] in self?.endDictation() }
        guard monitor.start() else { return false }
        hotkeyMonitor = monitor
        return true
    }

    // MARK: - Dictation flow

    private func beginDictation(mode: DictationMode) {
        guard case .idle = phase else {
            // A previous transcription is still running; cancel it and start fresh.
            transcriber.cancel()
            phase = .idle
            beginDictation(mode: mode)
            return
        }
        guard ModelManager.modelInstalled(for: mode) else {
            showAlert(
                title: "Model not downloaded",
                text: "The \(mode == .transcribe ? "transcription" : "translation") model is missing. Open Settings to download it."
            )
            openSettings()
            return
        }
        Log.write("dictation: hold start, mode=\(mode.rawValue)")
        // Spin up the whisper-server now so the model loads while the user speaks.
        WhisperServerManager.shared.preload(mode: mode)
        do {
            try recorder.start()
            phase = .recording(mode)
            hud.show(state: .recording(mode))
            NSSound(named: "Pop")?.play()
        } catch {
            showAlert(title: "Could not start recording", text: error.localizedDescription)
        }
    }

    private func endDictation() {
        guard case .recording(let mode) = phase else { return }
        guard let result = recorder.stop() else {
            // Too short or failed — treat as accidental tap.
            Log.write("dictation: recording too short, discarded")
            phase = .idle
            hud.hide()
            return
        }
        Log.write("dictation: recorded \(String(format: "%.1f", result.duration))s")
        phase = .processing(mode)
        hud.show(state: .processing)

        transcriber.transcribe(audioURL: result.fileURL, mode: mode) { [weak self] transcript in
            DispatchQueue.main.async {
                guard let self else { return }
                defer {
                    try? FileManager.default.removeItem(at: result.fileURL)
                    self.phase = .idle
                    self.hud.hide()
                }
                guard let transcript, !transcript.isEmpty else {
                    Log.write("dictation: empty transcript")
                    NSSound(named: "Basso")?.play()
                    return
                }
                Log.write("dictation: pasting \(transcript.count) chars")
                Paster.paste(transcript)
                NSSound(named: "Tink")?.play()
            }
        }
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appDelegate: self)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "WizFlow Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private func showAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
