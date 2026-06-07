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

    private(set) var phase: AppPhase = .idle {
        didSet { updateStatusIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestMicrophoneAccess()
        ensureAccessibilityPermission()
        startHotkeyMonitor()
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

    private func updateStatusIcon() {
        let symbolName: String
        let description: String
        switch phase {
        case .idle:
            symbolName = "mic"
            description = "WizFlow idle"
        case .recording:
            symbolName = "mic.fill"
            description = "WizFlow recording"
        case .processing:
            symbolName = "waveform"
            description = "WizFlow processing"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        if case .recording = phase {
            statusItem.button?.contentTintColor = .systemRed
        } else {
            statusItem.button?.contentTintColor = nil
        }
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

    private func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            showAlert(
                title: "Accessibility access needed",
                text: "WizFlow needs Accessibility access for the global hotkey and auto-paste.\n\nEnable WizFlow in System Settings → Privacy & Security → Accessibility, then relaunch."
            )
        }
    }

    // MARK: - Hotkey

    func startHotkeyMonitor() {
        hotkeyMonitor?.stop()
        let monitor = HotkeyMonitor(
            transcribeHotkey: Settings.transcribeHotkey,
            translateHotkey: Settings.translateHotkey
        )
        monitor.onHoldStart = { [weak self] mode in self?.beginDictation(mode: mode) }
        monitor.onHoldEnd = { [weak self] in self?.endDictation() }
        if !monitor.start() {
            showAlert(
                title: "Hotkey unavailable",
                text: "Could not install the global hotkey listener. Make sure Accessibility access is granted, then relaunch WizFlow."
            )
        }
        hotkeyMonitor = monitor
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
            phase = .idle
            hud.hide()
            return
        }
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
                    NSSound(named: "Basso")?.play()
                    return
                }
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
