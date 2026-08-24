import Foundation
import PushTextKit

/// What the menu says about a permission that is not granted (#6).
///
/// Separate from the probe and from the view because it is the part with a right and wrong answer:
/// `needsFirstGrant` and `grantBroken` produce the same OS reading and need opposite instructions,
/// and getting that backwards sends a user to a Settings list where the app is already ticked.
struct PermissionAdvice: Equatable {
    let title: String
    let detail: String
    let actionLabel: String
    /// Where the action goes. Nil only when the app can ask directly instead.
    let settingsURL: URL?
    /// True when the app itself can raise the system prompt, which is only ever the first ask.
    let canPromptInApp: Bool
    /// True when the fix is to CLEAR this app's stale TCC row before opening Settings (#136).
    ///
    /// Only a broken keyboard grant. TCC binds a grant to the app's code identity, so after a
    /// re-sign the listed entry belongs to a build that no longer exists and toggling it re-grants
    /// that old one - the user is left switching something that cannot work. Clearing the row is
    /// what lets the current app be granted. Ported from TermTile, which has shipped this for
    /// exactly the same reason.
    var repairs: Bool = false
    /// Which grant this row is about, so a repair knows what to reset.
    var permission: Permission?

    static func forStatus(_ status: PermissionStatus, of permission: Permission) -> PermissionAdvice? {
        let title = Self.title(of: permission)
        let pane = Self.settingsURL(for: permission)

        switch status {
        case .granted:
            return nil

        case .needsFirstGrant:
            // Only the microphone can be asked for from inside the app. Accessibility and PostEvent
            // have no programmatic prompt worth using - `AXIsProcessTrustedWithOptions` shows a
            // dialog that just sends the user to Settings anyway, with less context than this row.
            let canPrompt = permission == .microphone
            return PermissionAdvice(
                title: title,
                detail: "PushText has not been given \(Self.noun(of: permission)) access yet.",
                actionLabel: canPrompt ? "Allow..." : "Open Settings...",
                settingsURL: canPrompt ? nil : pane,
                canPromptInApp: canPrompt,
                permission: permission)

        case .grantBroken:
            return Self.repairAdvice(title: title, pane: pane, of: permission)

        case .denied:
            // A decision, not a fault. Stated as something they can revisit rather than an error.
            return PermissionAdvice(
                title: title,
                detail: "Access was declined. PushText cannot \(Self.capability(of: permission)) "
                    + "until it is turned on.",
                actionLabel: "Open Settings...",
                settingsURL: pane,
                canPromptInApp: false,
                permission: permission)
        }
    }

    /// A grant that worked and stopped, which is a different problem from never having asked.
    ///
    /// The microphone recovers by ASKING AGAIN, and the other two do not, because they are not the
    /// same situation underneath. `SystemPermissionProbe` derives a broken microphone grant from
    /// `AVAuthorizationStatus.notDetermined` - the same reading as a first grant, separated only by
    /// our own latch - and `requestAccess(for:)` prompts whenever the status is `.notDetermined`.
    /// So the prompt is available, and sending the user to System Settings instead is worse than a
    /// detour: with no TCC entry recorded there is nothing in that list to toggle.
    ///
    /// Accessibility and PostEvent break the other way. Their entry IS still in the list, ticked
    /// and ineffective, so "allow" is an instruction the user cannot follow and toggling off and on
    /// is what re-associates the grant with the new signature.
    private static func repairAdvice(title: String,
                                     pane: URL?,
                                     of permission: Permission) -> PermissionAdvice {
        guard permission == .microphone else {
            return PermissionAdvice(
                title: title,
                detail: "Access was granted before and has stopped working - usually after an "
                    + "update. System Settings may still list an older copy of PushText, which "
                    + "cannot be switched back on. Clear that entry and allow this copy.",
                actionLabel: "Reset & Open Settings...",
                settingsURL: pane,
                canPromptInApp: false,
                repairs: true,
                permission: permission)
        }
        return PermissionAdvice(
            title: title,
            detail: "Access was granted before and has stopped working - usually after an "
                + "update. PushText can ask for it again.",
            actionLabel: "Allow Again...",
            settingsURL: nil,
            canPromptInApp: true,
            permission: permission)
    }

    private static func title(of permission: Permission) -> String {
        switch permission {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .postEvent: "Input control"
        }
    }

    private static func noun(of permission: Permission) -> String {
        switch permission {
        case .microphone: "microphone"
        case .accessibility: "accessibility"
        case .postEvent: "input control"
        }
    }

    private static func capability(of permission: Permission) -> String {
        switch permission {
        case .microphone: "hear you"
        case .accessibility: "watch for the hotkey"
        case .postEvent: "insert text"
        }
    }

    /// PostEvent deliberately routes to the ACCESSIBILITY pane.
    ///
    /// Measured on macOS 26.6.2, not assumed: `Privacy_Accessibility` and `Privacy_Microphone` each
    /// appear once in `SecurityPrivacyExtension.appex`'s binary while `Privacy_PostEvent` and
    /// `Privacy_ListenEvent` appear zero times, and a deliberately fake anchor also scores zero, so
    /// the check discriminates. Opening the Accessibility anchor was then confirmed to land on a
    /// window titled "Accessibility". PostEvent has no pane of its own and is surfaced under
    /// Accessibility (docs/research/04 sec 4).
    private static func settingsURL(for permission: Permission) -> URL? {
        let anchor = permission == .microphone ? "Privacy_Microphone" : "Privacy_Accessibility"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
