import SwiftUI
import AppKit
import PushTextCore

/// The floating recording indicator (#46, supersedes #7).
///
/// **The constraint that shapes everything here: this panel must never become key.** Injection is a
/// synthetic Command-V sent to whatever has keyboard focus. If the HUD took focus, the paste would
/// land in the HUD instead of the user's document and dictation would silently stop working. Hence
/// `.nonactivatingPanel`, `canBecomeKey == false` and `canBecomeMain == false` - and the buttons
/// still receive mouse clicks, because a non-activating panel accepts clicks without taking focus.
///
/// It also has to be visible over full-screen apps, which is what `.canJoinAllSpaces` plus
/// `.fullScreenAuxiliary` buys; a plain window would simply not appear there.
final class DictationHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// What the HUD is currently telling the user.
enum HUDPhase: Equatable {
    case recording
    case working

    var label: String {
        switch self {
        case .recording: "Listening"
        case .working: "Transcribing"
        }
    }
}

/// The pill: cancel on top, live level in the middle, confirm at the bottom.
///
/// The bars are driven by a real `AudioLevelMeter` reading, never by an animation - a decorative
/// waveform would move while a dead capture path delivers nothing, which is precisely the failure
/// that made "is it even recording?" unanswerable.
struct DictationHUDView: View {
    let phase: HUDPhase
    let level: Double
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let barCount = 9

    var body: some View {
        VStack(spacing: 14) {
            control(symbol: "xmark", help: "Discard this dictation", action: onCancel)

            levels
                .frame(width: 34, height: 96)
                .accessibilityLabel(Text("\(phase.label), input level \(Int(level * 100)) percent"))

            control(symbol: "checkmark", help: "Finish and insert the text", action: onConfirm)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }

    /// Symmetric about the centre, tallest in the middle, so a low level reads as a flat line
    /// rather than as an empty box - stillness has to look deliberate.
    private var levels: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(phase == .recording ? Color.white : Color.white.opacity(0.45))
                    .frame(width: 3, height: barHeight(at: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let middle = Double(barCount - 1) / 2
        let distance = abs(Double(index) - middle) / middle          // 0 at centre, 1 at the edges
        let shape = 1 - (distance * distance) * 0.75                  // taller in the middle
        let minimum = 3.0
        let maximum = 88.0
        return CGFloat(minimum + (maximum - minimum) * level * shape)
    }

    private func control(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// Owns the panel and its lifetime.
@MainActor
final class DictationHUDController {
    private var panel: DictationHUDPanel?
    private let model: HUDModel

    init() {
        model = HUDModel()
    }

    /// Observable box so the panel's SwiftUI content updates without rebuilding the window.
    @Observable
    final class HUDModel {
        var phase: HUDPhase = .recording
        var level: Double = 0
        var onCancel: () -> Void = {}
        var onConfirm: () -> Void = {}
    }

    func show(phase: HUDPhase, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        model.phase = phase
        model.onCancel = onCancel
        model.onConfirm = onConfirm

        if panel == nil {
            panel = makePanel()
        }
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the latter would take focus and
        // break injection.
        panel?.orderFrontRegardless()
    }

    func update(phase: HUDPhase, level: Double) {
        model.phase = phase
        model.level = level
    }

    func hide() {
        model.level = 0
        panel?.orderOut(nil)
    }

    private func makePanel() -> DictationHUDPanel {
        let model = self.model
        let content = HUDHost(model: model)

        let panel = DictationHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 54, height: 190),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: content)

        position(panel)
        return panel
    }

    /// Right edge, vertically centred - out of the way of the caret, which is usually left of centre,
    /// while staying in peripheral vision.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.midY - size.height / 2))
    }
}

/// Bridges the observable box into the view.
private struct HUDHost: View {
    let model: DictationHUDController.HUDModel

    var body: some View {
        DictationHUDView(
            phase: model.phase,
            level: model.level,
            onCancel: model.onCancel,
            onConfirm: model.onConfirm)
    }
}
