import Testing
import Foundation
@testable import PushTextCore

/// Turning a raw `flagsChanged` event into "the user just chose this key" (#128).
///
/// Pure, because the alternative is testing a recorder by pressing keys at it. The two facts that
/// have to be right are both integer facts: WHICH key moved, and whether it moved DOWN.
@Suite("Hotkey recording")
struct HotkeyRecordingTests {

    /// The Globe key (#176).
    ///
    /// It was refused for months on a code comment that misread this repo's own research: the
    /// comment said a tap "cannot swallow" Globe and treated that as "cannot see" it. Detection
    /// works via `maskSecondaryFn`; only SUPPRESSION is impossible, because WindowServer runs the
    /// Globe action ahead of every tap.
    @Test("The Globe key is bindable")
    func globeIsCaptured() {
        #expect(HotkeyBinding.pressed(keyCode: 0x3F, rawModifierFlags: 0x0080_0000) == .globe)
    }

    /// Matching Globe by keycode ALONE loses it on exactly the machines this app targets:
    /// `sebsto/wispr` records that Apple Silicon may report a keycode other than 63 in
    /// `flagsChanged` for the Globe key.
    @Test("Globe is found by its flag even when the keycode is not 63")
    func globeMatchesByFlagNotKeycode() {
        #expect(HotkeyBinding.pressed(keyCode: 0x7F, rawModifierFlags: 0x0080_0000) == .globe)
    }

    /// Releasing Globe must not read as choosing it, the same as every other key.
    @Test("Releasing Globe captures nothing")
    func globeReleaseIsNotACapture() {
        #expect(HotkeyBinding.pressed(keyCode: 0x3F, rawModifierFlags: 0) == nil)
    }

    /// The five-key list was arbitrary and it is what cost Bobby the Globe key. Both sides of every
    /// held modifier are offered now.
    @Test("Every held modifier is offered, on both sides")
    func bothSidesAreSelectable() {
        let names = Set(HotkeyBinding.selectable.map(\.name))
        for expected in ["Right Option", "Left Option", "Right Command", "Left Command",
                         "Right Control", "Left Control", "Right Shift", "Left Shift",
                         "Globe (fn)"] {
            #expect(names.contains(expected), "\(expected) is not offered")
        }
    }

    /// Globe must never be the DEFAULT. Apple maps it to a vendor-specific HID usage, so a
    /// non-Apple keyboard emits no `maskSecondaryFn` at all - defaulting to it would hand those
    /// users a dead app with no error to show them.
    @Test("Globe is offered but is not the default")
    func globeIsNotTheDefault() {
        #expect(AppSettings.defaults.hotkeyBinding != .globe)
        #expect(AppSettings.defaults.hotkeyBinding == .rightOption)
    }

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
