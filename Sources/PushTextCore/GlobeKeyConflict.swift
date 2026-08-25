import Foundation

/// What macOS itself does when the Globe key is pressed (#176).
///
/// The Globe key is the one binding with a system action attached, and that action runs from
/// WindowServer **ahead of every event tap** - so PushText can see the press but cannot stop macOS
/// acting on it. Binding Globe while "Press the Globe key to" is set to anything but "Do Nothing"
/// means every dictation also opens the emoji viewer, switches input source, or starts Apple's own
/// dictation on top of ours.
///
/// **Read-only, deliberately.** `TISUpdateFnUsageType` would let the app set this itself, and
/// several shipping apps do exactly that - `OpenWhispr`, `Mojito`, `inputalk`, `Keyboop`. Do not
/// copy them: `Keyboop`'s own source comment names the hazard, which is that `kill -9` cannot be
/// intercepted, so a crash leaves the user's Globe key permanently dead **even after the app is
/// uninstalled**. An unrecoverable, uninstall-proof injury to someone's machine, through private
/// SPI that cannot be version-checked. Detect and ask; never write.
public enum GlobeKeyAction: Int, Equatable, Sendable {
    case doNothing = 0
    case changeInputSource = 1
    case showEmoji = 2
    case startDictation = 3

    /// How to name it to a user, matching System Settings' own wording.
    public var describedForUser: String {
        switch self {
        case .doNothing: return "Do Nothing"
        case .changeInputSource: return "Change Input Source"
        case .showEmoji: return "Show Emoji & Symbols"
        case .startDictation: return "Start Dictation"
        }
    }
}

public enum GlobeKeyConflict {

    /// Whether binding Globe will fight macOS, given the stored `AppleFnUsageType`.
    ///
    /// `nil` in - the key absent from the domain - is NOT treated as "fine". An absent value means
    /// the factory default, and on a Mac with a Globe key the factory default is not "Do Nothing".
    /// Reading absence as harmless is how this warning would stay silent on exactly the machines
    /// that need it.
    public static func conflict(fnUsageType: Int?) -> GlobeKeyAction? {
        guard let raw = fnUsageType else { return .changeInputSource }
        guard let action = GlobeKeyAction(rawValue: raw) else { return .changeInputSource }
        return action == .doNothing ? nil : action
    }
}
