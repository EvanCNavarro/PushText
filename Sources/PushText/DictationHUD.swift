import SwiftUI
import AppKit
import OSLog
import MacFaceKit
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
        VStack(spacing: 0) {
            // The pointer, so the panel reads as hanging FROM the menu-bar item - the same shape the
            // `···` overflow popover has. Without it the pill floats near the icon rather than
            // belonging to it.
            Pointer()
                .fill(Tokens.field)
                .frame(width: 16, height: 7)

            HStack(spacing: Tokens.inset) {
                control(symbol: "xmark", help: "Discard this dictation",
                        destructive: true, action: onCancel)

                levels
                    .frame(width: 96, height: 26)
                    .accessibilityLabel(Text("\(phase.label), input level \(Int(level * 100)) percent"))

                control(symbol: "checkmark", help: "Finish and insert the text", action: onConfirm)
            }
            .padding(.horizontal, Tokens.inset + 2)
            .padding(.vertical, Tokens.space + 1)
            // Same surface as the `···` dropdown: Tokens.field on a Tokens.line hairline, at the
            // design system's radius. The HUD is that component, not a lookalike.
            .background(
                RoundedRectangle(cornerRadius: Tokens.radius + 2, style: .continuous)
                    .fill(Tokens.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.radius + 2, style: .continuous)
                            .strokeBorder(Tokens.line, lineWidth: 1))
            )
        }
        .shadow(color: .black.opacity(0.4), radius: 16, y: 5)
    }

    /// Symmetric about the centre, tallest in the middle, so a low level reads as a flat line rather
    /// than as an empty box - stillness has to look deliberate.
    private var levels: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(phase == .recording ? Tokens.text : Tokens.quiet)
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

    /// Cancel is tinted with `Tokens.warning` and confirm stays neutral, so the destructive control
    /// is distinguishable at a glance rather than only by its glyph - the two sit a thumb apart and
    /// one of them throws the utterance away.
    private func control(symbol: String, help: String, destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(destructive ? Tokens.warning : Tokens.text)
                .frame(width: Tokens.controlButton, height: Tokens.controlButton)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.radius - 2, style: .continuous)
                        .fill(Tokens.row))
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

        // Re-anchor when the icon MOVES, which it does mid-utterance: macOS inserts its orange
        // recording indicator into the menu bar the moment capture starts, shifting every item
        // right. Anchoring only at show() left the pill a few points off-centre for the rest of
        // that utterance. Guarded on an actual change rather than repositioning on every 20 Hz
        // tick, so a still menu bar costs nothing.
        guard let panel, panel.isVisible, let anchor = statusItemAnchor() else { return }
        let wanted = origin(for: anchor, size: panel.frame.size)
        if abs(panel.frame.origin.x - wanted.x) > 0.5 || abs(panel.frame.origin.y - wanted.y) > 0.5 {
            dictationLog.info("HUD re-anchored \(panel.frame.origin.x) -> \(wanted.x)")
            panel.setFrameOrigin(wanted)
        }
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
            panel.setFrameOrigin(origin(for: anchor, size: size))
            return
        }

        // Fallback: under the right end of the menu bar, where the item lives on a stock system.
        panel.setFrameOrigin(NSPoint(
            x: full.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 4))
    }

    /// Where the panel's origin has to be for its pointer to sit under `anchor`, clamped so a pill
    /// hanging from an icon near the screen edge is not pushed off it.
    private func origin(for anchor: NSPoint, size: NSSize) -> NSPoint {
        let full = NSScreen.main?.frame ?? .zero
        return NSPoint(
            x: min(max(anchor.x - size.width / 2, full.minX + 8), full.maxX - size.width - 8),
            y: anchor.y - size.height - 4)
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

/// The little triangle that points at the menu-bar item, matching the `···` popover's arrow.
private struct Pointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
