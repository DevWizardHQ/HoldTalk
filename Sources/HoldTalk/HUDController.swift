import AppKit
import SwiftUI

/// A small floating, non-activating HUD near the bottom of the screen,
/// shown while recording or transcribing — like Wispr Flow's indicator.
final class HUDController {
    enum HUDState {
        case recording(DictationMode)
        case processing
    }

    private var panel: NSPanel?

    func show(state: HUDState) {
        let content = HUDView(state: state)
        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }
        guard let panel else { return }

        let hosting = NSHostingView(rootView: content)
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
    }
}

private struct HUDView: View {
    let state: HUDController.HUDState

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .recording(let mode):
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(mode == .translate ? "Listening (→ English)…" : "Listening…")
            case .processing:
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }
}
