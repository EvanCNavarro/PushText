import Testing
import AppKit
import CoreGraphics
import Carbon.HIToolbox
@testable import PushText
import PushTextCore

/// The recorder VIEW, driven by synthesized events (#128).
///
/// `HotkeyBinding.pressed` is tested in Core against integers; this covers the part that integers
/// cannot: that the view only listens while recording, that it tells the composition root to
/// silence the tap, and that it refuses what it cannot bind instead of storing it.
///
/// REQUIRES A WINDOW SERVER, and skips itself without one. Constructing an `NSView` initialises
/// AppKit, which on a machine with no GUI session blocks waiting for a WindowServer connection that
/// never arrives - and because Swift Testing runs one process, that wedges the WHOLE suite, not just
/// this file. Measured: the first CI run after this repository went public started all 36 suites and
/// then completed ZERO of 192 tests in 14 minutes, including pure-Foundation ones that touch no
/// AppKit at all. The identical suite had passed in 70 s on the private-repo runner minutes earlier.
///
/// `CGSessionCopyCurrentDictionary()` returns nil without a GUI session, which is the same condition
/// AppKit needs - so this gates on the actual requirement rather than on `CI`, and would also skip
/// correctly over SSH or from a launchd daemon.
/// Outside the suite on purpose: a trait that reads a static on the very type it is attached to is
/// a "circular reference resolving attached macro" and does not compile.
enum GUISession {
    static var isAvailable: Bool { CGSessionCopyCurrentDictionary() != nil }
}

@Suite("Hotkey recorder view", .enabled(if: GUISession.isAvailable))
@MainActor
struct HotkeyRecorderViewTests {

    /// `.flagsChanged` carries no characters; `keyEvent` still requires them, so they are empty.
    private func modifierEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .flagsChanged,
                         location: .zero,
                         modifierFlags: flags,
                         timestamp: 0,
                         windowNumber: 0,
                         context: nil,
                         characters: "",
                         charactersIgnoringModifiers: "",
                         isARepeat: false,
                         keyCode: keyCode)!
    }

    private func click(_ view: HotkeyRecorderView) {
        view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown,
                                                location: .zero,
                                                modifierFlags: [],
                                                timestamp: 0,
                                                windowNumber: 0,
                                                context: nil,
                                                eventNumber: 0,
                                                clickCount: 1,
                                                pressure: 1)!)
    }

    /// The whole gesture: click, press a bindable modifier, get it back.
    @Test("Clicking then pressing a bindable modifier captures it")
    func captureRoundTrip() {
        let view = HotkeyRecorderView()
        var captured: HotkeyBinding?
        view.onCapture = { captured = $0 }

        click(view)
        // Right Command: keyCode 0x36, device bit 0x10.
        view.flagsChanged(with: modifierEvent(keyCode: 0x36,
                                              flags: NSEvent.ModifierFlags(rawValue: 0x10)))
        #expect(captured == .rightCommand)
    }

    /// THE reason `onRecordingChange` exists. The event tap is global and does not care that a
    /// settings field has focus, so it has to be told to stand down - and told again when capture
    /// ends, or the hotkey stays dead until relaunch.
    @Test("Recording is announced on the way in AND on the way out")
    func recordingIsAnnouncedBothWays() {
        let view = HotkeyRecorderView()
        var signals: [Bool] = []
        view.onRecordingChange = { signals.append($0) }

        click(view)
        #expect(signals == [true], "the tap was never told to stand down")

        view.flagsChanged(with: modifierEvent(keyCode: 0x3D,
                                              flags: NSEvent.ModifierFlags(rawValue: 0x40)))
        #expect(signals == [true, false], "the tap was never re-armed")
    }

    /// A key the app cannot bind must not be stored, and must not end recording either - the user
    /// asked a question and deserves to keep answering it.
    @Test("An unbindable key is refused and recording continues")
    func unbindableKeyIsRefused() {
        let view = HotkeyRecorderView()
        var captured: HotkeyBinding?
        var signals: [Bool] = []
        view.onCapture = { captured = $0 }
        view.onRecordingChange = { signals.append($0) }

        click(view)
        // Left Command: a real modifier, deliberately absent from `selectable`.
        view.flagsChanged(with: modifierEvent(keyCode: 0x37,
                                              flags: NSEvent.ModifierFlags(rawValue: 0x000_8)))
        #expect(captured == nil)
        #expect(signals == [true], "recording ended on a key that was never accepted")
    }

    /// Before the click, the view is a label. Without this the recorder would capture whatever
    /// modifier the user happened to press while the menu was merely open.
    @Test("A key pressed before clicking is ignored")
    func idleViewIgnoresKeys() {
        let view = HotkeyRecorderView()
        var captured: HotkeyBinding?
        view.onCapture = { captured = $0 }

        view.flagsChanged(with: modifierEvent(keyCode: 0x3D,
                                              flags: NSEvent.ModifierFlags(rawValue: 0x40)))
        #expect(captured == nil)
    }

    /// Esc backs out without changing the binding, and re-arms the tap.
    @Test("Escape cancels and re-arms the tap")
    func escapeCancels() {
        let view = HotkeyRecorderView()
        var captured: HotkeyBinding?
        var signals: [Bool] = []
        view.onCapture = { captured = $0 }
        view.onRecordingChange = { signals.append($0) }

        click(view)
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                            timestamp: 0, windowNumber: 0, context: nil,
                                            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                            isARepeat: false, keyCode: UInt16(kVK_Escape))!)
        #expect(captured == nil)
        #expect(signals == [true, false])
    }

    /// The release half of a bindable key must not capture. `flagsChanged` fires twice per press,
    /// and taking the second one would record whatever the user let go of while reaching.
    @Test("Releasing the key is not a capture")
    func releaseDoesNotCapture() {
        let view = HotkeyRecorderView()
        var captured: HotkeyBinding?
        view.onCapture = { captured = $0 }

        click(view)
        view.flagsChanged(with: modifierEvent(keyCode: 0x3D, flags: []))
        #expect(captured == nil)
    }
}
