import Testing
import Foundation
@testable import PushTextCore

/// Which bound keys are consumed rather than passed on (#182).
///
/// Bobby: *"with whispr flow it overrides the default dictation with the globe thing, why doesn't
/// our app do that instead of like happening with it"*. Wispr binds keycode 63 as push-to-talk with
/// an ordinary tap and consumes it; PushText bound the same key and passed it through, so macOS ran
/// its own Globe action alongside ours.
@Suite("Hotkey suppression")
struct HotkeySuppressionTests {

    /// The whole feature. Globe has a system action attached that fires before we can be useful,
    /// and once it is the dictation key that action is purely in the way.
    @Test("Globe is consumed, so macOS does not also act on it")
    func globeIsSuppressed() {
        #expect(HotkeyBinding.globe.suppressesSystemAction)
    }

    /// The half that keeps the app usable. Consuming Right Shift would stop the user typing
    /// capitals; consuming Right Command would break every shortcut that uses it. Every other
    /// bindable modifier has a legitimate second job, and Globe - once bound to dictation - does not.
    @Test("Every other modifier is passed through untouched")
    func othersAreNotSuppressed() {
        let suppressing = HotkeyBinding.selectable.filter { $0.suppressesSystemAction }
        #expect(suppressing == [.globe],
                "these would be swallowed and break normal typing: \(suppressing.map(\.name))")
    }

    /// A press of some OTHER key must never be consumed just because Globe is bound - the tap sees
    /// every modifier, not only ours.
    @Test("Only the BOUND key is a candidate for suppression")
    func onlyTheBoundKeyIsConsidered() {
        // Globe bound, Right Option pressed: the flags carry no Fn bit, so nothing is consumed.
        #expect(HotkeyBinding.globe.shouldConsume(rawModifierFlags: 0x0000_0040) == false)
        // Globe bound, Globe pressed.
        #expect(HotkeyBinding.globe.shouldConsume(rawModifierFlags: 0x0080_0000))
        // Right Option bound, Right Option pressed: still passed through.
        #expect(HotkeyBinding.rightOption.shouldConsume(rawModifierFlags: 0x0000_0040) == false)
    }

    /// The RELEASE has to be consumed too. Letting the up-edge through leaves macOS seeing a bare
    /// Globe transition, which is the shape its own action watches for.
    @Test("The release is consumed as well as the press")
    func releaseIsAlsoConsumed() {
        #expect(HotkeyBinding.globe.shouldConsume(rawModifierFlags: 0x0080_0000))
        #expect(HotkeyBinding.globe.shouldConsumeRelease)
    }
}
