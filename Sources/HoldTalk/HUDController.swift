import AppKit
import SwiftUI

/// A floating, non-activating HUD near the bottom of the screen, styled like a
/// dictation pill: ✕ cancel — live waveform — ✓ submit.
/// Buttons are clickable without stealing focus from the target app.
final class HUDController {
    enum HUDState {
        case recording(DictationMode, handsFree: Bool)
        case processing
    }

    /// Wired by AppDelegate: ✕ and ✓ taps on the pill.
    var onCancel: (() -> Void)?
    var onSubmit: (() -> Void)?
    /// Live input level (0…1) for the waveform; wired to AudioRecorder.
    var levelProvider: (() -> Float)?

    private var panel: NSPanel?

    func show(state: HUDState) {
        let content = HUDView(
            state: state,
            level: { [weak self] in self?.levelProvider?() ?? 0 },
            onCancel: { [weak self] in self?.onCancel?() },
            onSubmit: { [weak self] in self?.onSubmit?() }
        )
        if panel == nil {
            let panel = NonFocusPanel(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        guard let panel else { return }

        // Only the recording pill has buttons; processing passes clicks through.
        if case .recording = state {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }

        let hosting = FirstMouseHostingView(rootView: content)
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil // stop the waveform timer
    }
}

/// Lets pill buttons react to the first click even though the panel never
/// becomes the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A panel that can never take keyboard focus: clicking ✕/✓ must leave the
/// user's text field focused so the paste lands where they were typing.
private final class NonFocusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Views

private struct HUDView: View {
    let state: HUDController.HUDState
    let level: () -> Float
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        Group {
            switch state {
            case .recording(let mode, let handsFree):
                HStack(spacing: 8) {
                    PillButton(symbol: "xmark", prominent: false, action: onCancel)
                        .help("Cancel dictation")
                    VStack(spacing: 1) {
                        WaveformView(level: level)
                        if handsFree {
                            Text("tap hotkey to stop")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.55))
                        } else if mode == .translate {
                            Text("→ English")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    PillButton(symbol: "checkmark", prominent: true, action: onSubmit)
                        .help("Finish & paste")
                }
            case .processing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                    Text("Transcribing…")
                        .foregroundStyle(.white)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.88), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .fixedSize()
    }
}

/// Round ✕ / ✓ button matching the dictation pill.
private struct PillButton: View {
    let symbol: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: 21, height: 21)
                .background(prominent ? Color.white : Color.white.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

/// Scrolling bar waveform driven by the REAL microphone level: newest sample
/// enters on the right and slides left — live "it's hearing you" feedback.
private struct WaveformView: View {
    let level: () -> Float
    @State private var samples = [Float](repeating: 0, count: 23)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            HStack(spacing: 2) {
                ForEach(samples.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.55 + 0.45 * Double(samples[i])))
                        .frame(width: 2.5, height: 3 + CGFloat(samples[i]) * 12)
                }
            }
            .frame(height: 15)
            .onChange(of: timeline.date) { _, _ in
                samples.removeFirst()
                samples.append(level())
            }
        }
    }
}
