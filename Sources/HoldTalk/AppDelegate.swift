import AppKit
import AVFoundation
import SwiftUI

enum DictationMode: String {
    case transcribe
    case translate
}

enum AppPhase {
    case idle
    case recording(DictationMode, handsFree: Bool)  // hold mode, or hands-free after a double-tap
    case pendingDoubleTap(DictationMode)            // quick tap; mic keeps recording briefly awaiting a 2nd tap
    case processing(DictationMode)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private var hotkeyMonitor: HotkeyMonitor?
    private let hud = HUDController()
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var accessibilityPollTimer: Timer?
    private var statusMenu: NSMenu?
    private var holdStartedAt: Date?
    private var pendingTapTimer: Timer?
    private let tapThreshold: TimeInterval = 0.35    // press shorter than this = a tap
    private let doubleTapWindow: TimeInterval = 0.45 // max gap between the two taps

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

        hud.onCancel = { [weak self] in self?.cancelFromHUD() }
        hud.onSubmit = { [weak self] in self?.submitFromHUD() }
        hud.levelProvider = { [weak self] in self?.recorder.level() ?? 0 }

        UpdateManager.shared.onUpdateAvailable = { [weak self] release in
            self?.showUpdateMenuItem(version: release.version)
        }
        UpdateManager.shared.startAutomaticChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WhisperServerManager.shared.shutdownAll()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon()

        let menu = NSMenu()
        let holdInfo = menuItem("Hold hotkey to dictate", symbol: "mic.badge.plus", action: nil)
        holdInfo.isEnabled = false
        menu.addItem(holdInfo)
        menu.addItem(.separator())
        menu.addItem(menuItem("History…", symbol: "clock.arrow.circlepath", action: #selector(openHistory), keyEquivalent: "h"))
        menu.addItem(menuItem("Settings…", symbol: "gearshape", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(menuItem("Check for Updates…", symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit HoldTalk", symbol: "power", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusMenu = menu
    }

    private func menuItem(_ title: String, symbol: String, action: Selector?,
                          keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    // MARK: - Updates

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates(userInitiated: true)
    }

    /// Adds an "Install HoldTalk x.y.z…" item at the top of the menu when an
    /// update is found by a background check.
    private func showUpdateMenuItem(version: String) {
        guard let menu = statusMenu,
              !menu.items.contains(where: { $0.action == #selector(installUpdate) }) else { return }
        let item = NSMenuItem(title: "⬆ Install HoldTalk \(version)…",
                              action: #selector(installUpdate), keyEquivalent: "")
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func installUpdate() {
        guard let release = UpdateManager.shared.availableRelease else { return }
        UpdateManager.shared.install(release)
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
            setSymbolIcon("mic", description: "HoldTalk idle", tint: nil)
        case .recording, .pendingDoubleTap:
            setSymbolIcon("mic.fill", description: "HoldTalk recording", tint: .systemRed)
        case .processing:
            setSymbolIcon("waveform", description: "HoldTalk processing", tint: nil)
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
                        text: "Enable HoldTalk in System Settings → Privacy & Security → Microphone, then relaunch."
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
        monitor.onHoldStart = { [weak self] mode in self?.onHotkeyDown(mode: mode) }
        monitor.onHoldEnd = { [weak self] in self?.onHotkeyUp() }
        guard monitor.start() else { return false }
        hotkeyMonitor = monitor
        return true
    }

    // MARK: - Dictation flow
    //
    // Two ways to dictate with the same hotkey:
    //   HOLD:       press & hold → talk → release → transcribe.
    //   HANDS-FREE: double-tap → talk freely → single tap → transcribe.

    private func onHotkeyDown(mode: DictationMode) {
        switch phase {
        case .idle:
            holdStartedAt = Date()
            beginRecording(mode: mode)
        case .pendingDoubleTap(let pendingMode):
            // Second tap in time → hands-free; the mic never stopped recording.
            pendingTapTimer?.invalidate()
            pendingTapTimer = nil
            Log.write("dictation: hands-free engaged")
            phase = .recording(pendingMode, handsFree: true)
            hud.show(state: .recording(pendingMode, handsFree: true))
        case .recording(_, handsFree: true):
            // Tap while hands-free → stop & transcribe.
            Log.write("dictation: hands-free stop tap")
            finishRecording()
        case .recording:
            break // already holding; ignore
        case .processing:
            // A previous transcription is still running; cancel it and start fresh.
            transcriber.cancel()
            phase = .idle
            holdStartedAt = Date()
            beginRecording(mode: mode)
        }
    }

    private func onHotkeyUp() {
        guard case .recording(let mode, handsFree: false) = phase else { return }
        let heldDuration = holdStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        if heldDuration < tapThreshold {
            // Quick tap — keep recording briefly in case a second tap follows.
            enterPendingDoubleTap(mode: mode)
        } else {
            finishRecording()
        }
    }

    private func beginRecording(mode: DictationMode) {
        guard ModelManager.modelInstalled(for: mode) else {
            showAlert(
                title: "Model not downloaded",
                text: "The \(mode == .transcribe ? "transcription" : "translation") model is missing. Open Settings to download it."
            )
            openSettings()
            return
        }
        Log.write("dictation: start, mode=\(mode.rawValue)")
        // Spin up the whisper-server now so the model loads while the user speaks.
        WhisperServerManager.shared.preload(mode: mode)
        do {
            try recorder.start()
            phase = .recording(mode, handsFree: false)
            hud.show(state: .recording(mode, handsFree: false))
            NSSound(named: "Pop")?.play()
        } catch {
            showAlert(title: "Could not start recording", text: error.localizedDescription)
        }
    }

    private func enterPendingDoubleTap(mode: DictationMode) {
        phase = .pendingDoubleTap(mode)
        pendingTapTimer?.invalidate()
        pendingTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
            guard let self, case .pendingDoubleTap = self.phase else { return }
            // Single short tap — accidental; discard the recording.
            Log.write("dictation: single tap, discarded")
            self.recorder.cancel()
            self.phase = .idle
            self.hud.hide()
        }
    }

    /// ✕ on the HUD pill.
    private func cancelFromHUD() {
        switch phase {
        case .recording, .pendingDoubleTap:
            Log.write("dictation: cancelled from HUD")
            pendingTapTimer?.invalidate()
            pendingTapTimer = nil
            recorder.cancel()
            phase = .idle
            hud.hide()
        default:
            break
        }
    }

    /// ✓ on the HUD pill.
    private func submitFromHUD() {
        switch phase {
        case .recording, .pendingDoubleTap:
            Log.write("dictation: submitted from HUD")
            finishRecording()
        default:
            break
        }
    }

    private func finishRecording() {
        let mode: DictationMode
        switch phase {
        case .recording(let m, _), .pendingDoubleTap(let m):
            mode = m
        default:
            return
        }
        pendingTapTimer?.invalidate()
        pendingTapTimer = nil

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
                HistoryStore.shared.add(transcript)
                Paster.paste(transcript)
                NSSound(named: "Tink")?.play()
            }
        }
    }

    // MARK: - History

    @objc private func openHistory() {
        if historyWindow == nil {
            let hosting = NSHostingController(rootView: HistoryView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "HoldTalk History"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        historyWindow?.center()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appDelegate: self)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "HoldTalk Settings"
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
