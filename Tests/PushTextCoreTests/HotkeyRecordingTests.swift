import Testing
import Foundation
@testable import PushTextCore

/// Turning a raw `flagsChanged` event into "the user just chose this key" (#128).
///
/// Pure, because the alternative is testing a recorder by pressing keys at it. The two facts that
/// have to be right are both integer facts: WHICH key moved, and whether it moved DOWN.
@Suite("Hotkey recording")
struct HotkeyRecordingTests {

    /// A press: the key's own device bit is set in the flags that arrived with the event.
    @Test("A supported modifier going down is captured")
    func pressIsCaptured() {
        let binding = HotkeyBinding.pressed(keyCode: 0x3D, rawModifierFlags: 0x40)
        #expect(binding == .rightOption)
    }

    /// THE case that makes a recorder feel broken. `flagsChanged` fires on the way down AND on the
    /// way up; capturing the release would either double-fire or record the key the user just let
    /// go of while reaching for another.
    @Test("The same key going up is not a capture")
    func releaseIsIgnored() {
        #expect(HotkeyBinding.pressed(keyCode: 0x3D, rawModifierFlags: 0) == nil)
    }

    /// Right Control is `0x2000`, nowhere near left Control's `0x1` - the asymmetry `HotkeyBinding`
    /// exists to encode. Asserted here so a recorder cannot quietly re-derive it by doubling.
    @Test("Right Control's device bit is honoured, not inferred")
    func rightControlUsesItsRealBit() {
        #expect(HotkeyBinding.pressed(keyCode: 0x3E, rawModifierFlags: 0x2000) == .rightControl)
        // 0x2 is left SHIFT. A recorder that doubled left-Control's 0x1 would accept this.
        #expect(HotkeyBinding.pressed(keyCode: 0x3E, rawModifierFlags: 0x2) == nil)
    }

    /// The non-vacuous one: flags are NOT merely non-empty, they must contain THIS key's bit.
    /// Holding Right Control and tapping Right Option must not record Right Option as pressed on the
    /// strength of someone else's bit.
    @Test("Another key's bit does not count as this key going down")
    func aDifferentKeysBitIsNotAPress() {
        #expect(HotkeyBinding.pressed(keyCode: 0x3D, rawModifierFlags: 0x2000) == nil)
    }

    /// The recorder must not promise more than the app can bind. Fn is deliberately absent from
    /// `selectable` because an event tap cannot swallow it, and an ordinary key is not a
    /// push-to-talk modifier at all.
    @Test("A key the app cannot bind is refused")
    func unsupportedKeysAreRefused() {
        #expect(HotkeyBinding.pressed(keyCode: 0x31, rawModifierFlags: 0x40) == nil)   // Space
        #expect(HotkeyBinding.pressed(keyCode: 0x37, rawModifierFlags: 0x100000) == nil) // L-Command
    }

    /// Every offered binding must be recordable, or the picker and the recorder disagree about what
    /// the app supports - which is the defect that made this a list in the first place.
    @Test("Every selectable binding can be captured by its own bit")
    func everySelectableBindingRoundTrips() {
        for binding in HotkeyBinding.selectable {
            #expect(HotkeyBinding.pressed(keyCode: binding.keyCode,
                                          rawModifierFlags: binding.deviceMask) == binding,
                    "\(binding.name) is offered but cannot be recorded")
        }
    }
}
