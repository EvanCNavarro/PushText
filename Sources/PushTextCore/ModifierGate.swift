import Foundation

/// Which key press-and-hold starts a dictation.
///
/// A push-to-talk binding is a *bare held modifier*, which is an awkward thing on macOS and is why
/// this is modelled explicitly rather than as a `CGEventFlags` comparison at the call site.
///
/// Two properties make it work, and both are easy to get wrong:
///
/// 1. **Side matters.** `CGEventFlags.maskAlternate` is a UNION — it is set while *either* Option
///    key is down. Watching it means that holding left-Option and then tapping right-Option produces
///    no observable right-Option release, because the union bit never clears. The microphone then
///    stays open with nothing to close it. The device-dependent bits below distinguish the sides.
/// 2. **The bits are not symmetric.** Right-Control is `0x2000`, nowhere near left-Control's `0x1`.
///    Inferring a right-side bit by doubling the left-side one yields left-Shift for Control.
///
/// Values read from `IOKit/hidsystem/IOLLEvent.h` and `HIToolbox/Events.h` in the macOS 15.2 SDK,
/// not from memory.
public struct HotkeyBinding: Equatable, Hashable, Sendable {
    /// Virtual keycode of the physical key (`kVK_*`). Present for diagnostics and for the
    /// key-down/key-up path; the flag mask is what actually decides held-ness.
    public let keyCode: Int64
    /// The device-dependent modifier bit for this specific physical key
    /// (`NX_DEVICE*KEYMASK`), which is side-specific where the public `CGEventFlags` masks are not.
    public let deviceMask: UInt64
    /// Human-readable name, for the settings UI and log lines.
    public let name: String

    public init(keyCode: Int64, deviceMask: UInt64, name: String) {
        self.keyCode = keyCode
        self.deviceMask = deviceMask
        self.name = name
    }

    // NX_DEVICERALTKEYMASK 0x40, kVK_RightOption 0x3D.
    public static let rightOption = HotkeyBinding(
        keyCode: 0x3D, deviceMask: 0x0000_0040, name: "Right Option")
    // NX_DEVICERCMDKEYMASK 0x10, kVK_RightCommand 0x36.
    public static let rightCommand = HotkeyBinding(
        keyCode: 0x36, deviceMask: 0x0000_0010, name: "Right Command")
    // NX_DEVICERCTLKEYMASK 0x2000 — NOT 0x2, which is left Shift. kVK_RightControl 0x3E.
    public static let rightControl = HotkeyBinding(
        keyCode: 0x3E, deviceMask: 0x0000_2000, name: "Right Control")
    // NX_DEVICERSHIFTKEYMASK 0x4, kVK_RightShift 0x3C.
    public static let rightShift = HotkeyBinding(
        keyCode: 0x3C, deviceMask: 0x0000_0004, name: "Right Shift")
    // NX_DEVICELALTKEYMASK 0x20, kVK_Option 0x3A. Offered for completeness; right-side is the default.
    public static let leftOption = HotkeyBinding(
        keyCode: 0x3A, deviceMask: 0x0000_0020, name: "Left Option")

    // NX_DEVICELCMDKEYMASK 0x8, kVK_Command 0x37.
    public static let leftCommand = HotkeyBinding(
        keyCode: 0x37, deviceMask: 0x0000_0008, name: "Left Command")
    // NX_DEVICELCTLKEYMASK 0x1, kVK_Control 0x3B.
    public static let leftControl = HotkeyBinding(
        keyCode: 0x3B, deviceMask: 0x0000_0001, name: "Left Control")
    // NX_DEVICELSHIFTKEYMASK 0x2, kVK_Shift 0x38.
    public static let leftShift = HotkeyBinding(
        keyCode: 0x38, deviceMask: 0x0000_0002, name: "Left Shift")

    /// The Globe key. `kCGEventFlagMaskSecondaryFn` / `NSEvent.ModifierFlags.function`, which are
    /// bit-identical at 0x800000, and `kVK_Function` 0x3F.
    ///
    /// **It was excluded on a comment that misread our own research (#176).** That comment said the
    /// Globe key "never enters the event-tap chain at all, so an event tap cannot swallow it" - and
    /// conflated two different facts. `docs/research/04` says a tap CAN SEE Fn via this flag, and
    /// that what cannot be done is SUPPRESS it, because WindowServer runs the Globe action ahead of
    /// every tap. Its actual recommendation was "Fn/Globe offered as an opt-in ... Do NOT default to
    /// Fn", and "not the default" became "not available".
    ///
    /// Not the default, for the reason that report gives: Apple maps Globe to a vendor-specific HID
    /// usage, so a non-Apple keyboard produces no `maskSecondaryFn` at all and would leave those
    /// users with a dead app and no error to show them.
    public static let globe = HotkeyBinding(
        keyCode: 0x3F, deviceMask: 0x0080_0000, name: "Globe (fn)")

    /// The bindings offered in settings.
    /// The binding a raw `flagsChanged` event just pressed DOWN, or nil (#128).
    ///
    /// Two conditions, and a recorder that drops either one feels broken in a different way:
    ///
    /// 1. **The key must be one we can bind.** `selectable` is the whole offer; anything else is
    ///    refused rather than stored, or the settings UI promises a binding the event tap will never
    ///    honour.
    /// 2. **The key must be going DOWN.** `flagsChanged` fires on the way down and again on the way
    ///    up, and the direction is only readable from the flags: the key's own device bit is set
    ///    while it is held and clear once it is released. Capturing the release would record the key
    ///    the user just let go of while reaching for the next one.
    ///
    /// The bit tested is THIS key's `deviceMask`, never "are the flags non-empty" - holding Right
    /// Control while tapping Right Option must not record Right Option on the strength of Control's
    /// bit.
    ///
    /// Takes integers rather than an `NSEvent` so the decision is testable without a keyboard, a
    /// window, or AppKit in Core.
    public static func pressed(keyCode: Int64, rawModifierFlags: UInt64) -> HotkeyBinding? {
        if let binding = selectable.first(where: { $0.keyCode == keyCode }) {
            return (rawModifierFlags & binding.deviceMask) != 0 ? binding : nil
        }
        // GLOBE, by flag rather than keycode. `sebsto/wispr` ships a comment recording that Apple
        // Silicon Macs may report a keycode other than 63 in `flagsChanged` for the Globe key, so
        // matching on the keycode alone loses it on exactly the machines this app targets
        // (docs/research/04 sec 1.3).
        //
        // Safe here BECAUSE this only ever sees `flagsChanged`. The Fn bit is also set on F1-F20 and
        // the arrow keys on a laptop keyboard - and those arrive as `keyDown`, never as a modifier
        // change. Testing the flag on a `keyDown` stream would be the false-positive trap that
        // research names.
        if (rawModifierFlags & globe.deviceMask) != 0 { return globe }
        return nil
    }

    public static let selectable: [HotkeyBinding] = [
        .rightOption, .rightCommand, .rightControl, .rightShift,
        .leftOption, .leftCommand, .leftControl, .leftShift,
        .globe
    ]
}

/// Which way a push-to-talk key just moved.
public enum HotkeyEdge: Equatable, Sendable {
    case pressed
    case released
}

/// Turns a stream of raw modifier-flag snapshots into press/release edges for ONE bound key.
///
/// `flagsChanged` events report the whole new modifier state rather than a delta, and they fire for
/// *every* modifier — so the same event arrives when an unrelated key moves. This holds the previous
/// held-ness of the bound key and emits an edge only when that specific bit actually changes.
///
/// Pure and synchronous, so the side-matters behaviour above is testable with no event tap, no
/// permissions, and no keyboard.
public struct ModifierGate: Sendable {
    public let binding: HotkeyBinding
    public private(set) var isDown: Bool

    public init(binding: HotkeyBinding, isDown: Bool = false) {
        self.binding = binding
        self.isDown = isDown
    }

    /// Feed the raw flags from a `flagsChanged` event.
    ///
    /// - Returns: the edge, or `nil` when the bound key's state did not change.
    public mutating func update(flags: UInt64) -> HotkeyEdge? {
        let nowDown = isHeld(in: flags)
        guard nowDown != isDown else { return nil }
        isDown = nowDown
        return nowDown ? .pressed : .released
    }

    /// Whether the bound key is held in this flag snapshot, ignoring every other modifier.
    public func isHeld(in flags: UInt64) -> Bool {
        flags & binding.deviceMask != 0
    }
}
