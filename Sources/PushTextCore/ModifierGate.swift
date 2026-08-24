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

    /// The bindings offered in settings. Fn is deliberately absent: it does not exist on non-Apple
    /// keyboards, and its system action cannot be suppressed — `TextInputSwitcher.app` handles the
    /// Globe key through `_CGSSetSymbolicHotKey` and never enters the event-tap chain at all, so an
    /// event tap cannot swallow it. See docs/research/04 sec 1 and sec 2.
    public static let selectable: [HotkeyBinding] = [
        .rightOption, .rightCommand, .rightControl, .rightShift, .leftOption
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
