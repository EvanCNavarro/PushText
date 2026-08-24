// @preconcurrency: the SDK imports kAXTrustedCheckOptionPrompt as a mutable global
// (`public var ...: Unmanaged<CFString>`), which Swift 6 strict concurrency rejects on a plain
// import. Same note TermTile carries.
@preconcurrency import ApplicationServices
import Foundation

/// Asking macOS for Accessibility trust - which is also what puts this app in the list (#146).
///
/// **The prompt is not merely a dialog.** `PermissionAdvice` used to say it "shows a dialog that
/// just sends the user to Settings anyway, with less context than this row", and on that reasoning
/// PushText never called it. The consequence was that System Settings had no PushText row to switch
/// on: the Accessibility list contains apps that have REQUESTED the permission, and PushText never
/// asked. Bobby opened the pane after a Reset and found twenty apps, none of them this one.
///
/// So the prompting call is the registration step. Reset removes the stale row; this puts a fresh
/// one back, bound to the CURRENT code identity, which is the whole point of having reset it.
public enum AccessibilityTrust {

    /// Deep link to the pane where the user flips the switch.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// - Parameter prompting: true asks macOS to show the grant dialog when untrusted, and registers
    ///   this app so the Accessibility list has something to toggle.
    /// - Returns: whether this process is trusted RIGHT NOW. False immediately after prompting is
    ///   normal and not a failure - the user has not answered yet.
    @discardableResult
    public static func isTrusted(prompting: Bool) -> Bool {
        let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)
    }
}
