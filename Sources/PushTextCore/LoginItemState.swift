import Foundation

/// Whether macOS will start PushText at login (#162).
///
/// Three states, not a Bool, because `requiresApproval` is a real thing macOS does and it is the one
/// that makes a toggle lie. Registration can succeed while the login item sits disabled in System
/// Settings awaiting the user - a Bool would draw that as ON, and the app would not start at the
/// next login, and nothing on screen would explain why.
public enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but macOS wants the user to approve it in System Settings first.
    case requiresApproval

    /// What the toggle should show. `requiresApproval` reads as ON because the user DID ask for it -
    /// the switch reflects their intent, and the notice beside it explains why it is not in force
    /// yet. Drawing it OFF would invite them to toggle it again, which does nothing.
    public var isOn: Bool { self != .disabled }

    /// Whether the user has to go and do something before this takes effect.
    public var needsUserApproval: Bool { self == .requiresApproval }
}
