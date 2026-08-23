import SwiftUI
import AppKit
import OSLog
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
    /// Nothing happening. A small quiet pill, so the affordance is discoverable without shouting.
    case resting
    case recording
    case working

    var label: String {
        switch self {
        case .resting: "Ready"
        case .recording: "Listening"
        case .working: "Transcribing"
        }
    }

    var isActive: Bool { self != .resting }
}

/// The pill. Horizontal: cancel on the left, live level in the middle, confirm on the right.
///
/// Resting it is a small outline; active it expands around the controls. One view rather than two,
/// so the transition is a size change on the same shape instead of a swap between two windows -
/// which is what makes it read as the same object growing.
///
/// The bars are driven by a real `AudioLevelMeter` reading, never by an animation: a decorative
/// waveform would move while a dead capture path delivers nothing, which is precisely the failure
/// that made "is it even recording?" unanswerable.
struct DictationHUDView: View {
    let phase: HUDPhase
    let level: Double
    /// Drives the drop-down transition. Separate from `phase` because the pill has to be MOUNTED
    /// before it can animate in - flipping it after the panel is on screen is what makes the motion
    /// happen at all.
    let isPresented: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let barCount = 13

    var body: some View {
        VStack(spacing: 0) {
            if isPresented {
                active
                    // Enters and leaves through the TOP edge, so it reads as dropping out of the
                    // menu-bar item it hangs from. A default transition scales from the view's
                    // centre inside a wider panel, which looks like it slides in from a corner -
                    // which is exactly what it looked like.
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        // Pinned to the TOP of the panel and centred horizontally, so the pill hangs from the same
        // point regardless of how wide it grows.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isPresented)
        .animation(.spring(response: 0.30, dampingFraction: 0.78), value: phase)
    }

    private var active: some View {
        HStack(spacing: 12) {
            control(symbol: "xmark", help: "Discard this dictation", action: onCancel)

            levels
                .frame(width: 96, height: 26)
                .accessibilityLabel(Text("\(phase.label), input level \(Int(level * 100)) percent"))

            control(symbol: "checkmark", help: "Finish and insert the text", action: onConfirm)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 5)
    }

    /// Symmetric about the centre, tallest in the middle, so a low level reads as a flat line rather
    /// than as an empty box - stillness has to look deliberate.
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
        let maximum = 24.0
        return CGFloat(minimum + (maximum - minimum) * level * shape)
    }

    private func control(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
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
    private let model = HUDModel()

    /// Observable box so the panel's SwiftUI content updates without rebuilding the window.
    @Observable
    final class HUDModel {
        var phase: HUDPhase = .resting
        var isPresented = false
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
        // Re-anchor on every show: the status item moves when other menu-bar apps come and go, and
        // a position captured once would drift away from the icon it is supposed to hang from.
        position(panel!)
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the latter would take focus and
        // break injection.
        panel?.orderFrontRegardless()

        // Mount first, animate second. Setting this in the same turn as ordering the window front
        // would show the pill already in place with nothing to animate.
        model.isPresented = false
        DispatchQueue.main.async { [model] in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                model.isPresented = true
            }
        }
    }

    func update(phase: HUDPhase, level: Double) {
        model.phase = phase
        model.level = phase.isActive ? level : 0
    }

    /// Drops back up out of sight. The HUD exists only while an utterance does - it hangs from the
    /// menu-bar item rather than living on screen, so there is nothing to dismiss when idle.
    func hide() {
        model.level = 0
        guard let panel, panel.isVisible else {
            model.isPresented = false
            model.phase = .resting
            return
        }
        // Let it retract through the top edge before the window goes away, or the animation is
        // replaced by the panel simply vanishing.
        withAnimation(.easeIn(duration: 0.16)) { model.isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, self.model.isPresented == false else { return }
            self.model.phase = .resting
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> DictationHUDPanel {
        let content = HUDHost(model: model)

        // Sized for the ACTIVE state and never resized: the pill animates inside a fixed, fully
        // transparent panel, so growing it cannot cause a window-server flicker or move the click
        // targets around mid-animation.
        let panel = DictationHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 76),
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

    /// Hangs directly under the menu-bar item, like a slim dropdown.
    ///
    /// The anchor is the real status-item window when it can be found, so the pill tracks the icon
    /// as other menu-bar apps push it around. `MenuBarExtra` does not hand out its `NSStatusItem`,
    /// so the window is located by class name - which is why there is a fallback rather than a
    /// force-unwrap: a private class name is not a contract, and the HUD must still appear if
    /// Apple renames it.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let full = screen.frame

        let anchor = statusItemAnchor()
        dictationLog.info("HUD anchor=\(anchor.map { "\($0.x),\($0.y)" } ?? "none (fallback)", privacy: .public)")
        if let anchor {
            panel.setFrameOrigin(NSPoint(
                x: min(max(anchor.x - size.width / 2, full.minX + 8), full.maxX - size.width - 8),
                y: anchor.y - size.height - 4))
            return
        }

        // Fallback: under the right end of the menu bar, where the item lives on a stock system.
        panel.setFrameOrigin(NSPoint(
            x: full.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 4))
    }

    /// Centre-bottom of our status-item window, in screen coordinates.
    private func statusItemAnchor() -> NSPoint? {
        for window in NSApp.windows {
            let name = NSStringFromClass(type(of: window))
            guard name.contains("StatusBar") || name.contains("MenuBarExtra") else { continue }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            return NSPoint(x: frame.midX, y: frame.minY)
        }
        return nil
    }
}

/// Bridges the observable box into the view.
private struct HUDHost: View {
    let model: DictationHUDController.HUDModel

    var body: some View {
        DictationHUDView(
            phase: model.phase,
            level: model.level,
            isPresented: model.isPresented,
            onCancel: model.onCancel,
            onConfirm: model.onConfirm)
    }
}
