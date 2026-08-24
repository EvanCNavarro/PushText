import AppKit
import Carbon.HIToolbox
import MacFaceKit
import PushTextCore
import SwiftUI

/// Click-to-record field for the dictation key (#128), matching TermTile's shortcut recorder.
///
/// Ported rather than shared, because the capture is not the same problem. TermTile records a CHORD
/// and reads it from `keyDown`; PushText binds a BARE HELD MODIFIER, which never produces a
/// `keyDown` at all - it arrives as `flagsChanged`, and the direction of travel is only readable
/// from the flags. A shared component would have to be two components wearing one name.
///
/// The drawing, the focus dance and the Esc handling ARE the same, and are TermTile's: a
/// self-contained focusable `NSView` that draws itself and grabs first responder on its own
/// `mouseDown`. SwiftUI has no native recorder, and a Button-plus-background version fails in a
/// popover because the Button keeps keyboard focus and the capture view never becomes first
/// responder.
struct HotkeyRecorder: NSViewRepresentable {
    let current: HotkeyBinding
    /// Called with true when capture starts and false when it ends, so the composition root can
    /// silence the event tap. Without it, pressing Right Option to REBIND also starts a dictation:
    /// the tap is global and does not care that a settings field has focus.
    let onRecordingChange: (Bool) -> Void
    let onCapture: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let view = HotkeyRecorderView()
        view.onCapture = onCapture
        view.onRecordingChange = onRecordingChange
        view.update(current: current)
        return view
    }

    func updateNSView(_ view: HotkeyRecorderView, context: Context) {
        view.onCapture = onCapture
        view.onRecordingChange = onRecordingChange
        view.update(current: current)
    }
}

final class HotkeyRecorderView: NSView {
    var onCapture: ((HotkeyBinding) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var current = HotkeyBinding.rightOption
    private var recording = false {
        didSet {
            guard recording != oldValue else { return }
            onRecordingChange?(recording)
        }
    }

    /// Refresh the displayed key from the model - but never mid-capture, which would stomp the
    /// "Press keys..." prompt the user is currently answering.
    func update(current: HotkeyBinding) {
        guard !recording else { return }
        self.current = current
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        // A distinct field colour so the recorder reads as an input on the dark panel, rather than
        // as the near-panel-coloured system control background.
        (recording ? Tokens.nsAccent.withAlphaComponent(0.18) : Tokens.nsField).setFill()
        path.fill()
        (recording ? Tokens.nsAccent : Tokens.nsLine).setStroke()
        path.stroke()

        let text = recording ? "Press a key..." : current.name
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: recording ? Tokens.nsAccent : Tokens.nsText
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attrs)
    }

    /// The click that starts recording ALSO focuses this view, in one gesture. A separate button
    /// that toggled state and hoped focus followed is what fails inside a popover.
    override func mouseDown(with event: NSEvent) {
        recording.toggle()
        window?.makeFirstResponder(recording ? self : nil)
        needsDisplay = true
    }

    /// The capture itself. A bare modifier only ever arrives here - it produces no `keyDown`.
    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        guard let binding = HotkeyBinding.pressed(keyCode: Int64(event.keyCode),
                                                  rawModifierFlags: UInt64(event.modifierFlags.rawValue))
        else {
            // A key we cannot bind, or the release half of a key we can. Releases are SILENT - the
            // user has done nothing wrong by letting go - while an unbindable key beeps.
            if HotkeyBinding.selectable.allSatisfy({ $0.keyCode != Int64(event.keyCode) }) {
                NSSound.beep()
            }
            return
        }
        finish(with: binding)
    }

    /// Esc cancels. It is an ordinary key, so it arrives as `keyDown` rather than through the path
    /// above - and anything else typed while recording is swallowed rather than passed on, so a
    /// stray letter cannot reach the app behind the popover.
    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            endRecording()
        } else {
            NSSound.beep()
        }
    }

    /// Clicking away or dismissing the popover ends capture cleanly, which is what re-arms the tap.
    override func resignFirstResponder() -> Bool {
        endRecording()
        return true
    }

    private func finish(with binding: HotkeyBinding) {
        current = binding
        endRecording()
        onCapture?(binding)
    }

    private func endRecording() {
        guard recording else { return }
        recording = false
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }
}
