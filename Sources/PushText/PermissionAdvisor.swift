import Foundation
import PushTextKit

/// Turns live permission state into menu rows (#6).
///
/// A collaborator rather than an extension because it owns STATE, and Swift extensions cannot hold
/// stored properties - the constraint that decided this shape after two attempts to split it as an
/// extension failed. Same reasoning as `CaptureWatchdog` and `ModelPreparer`: it changes when OS
/// grant handling changes, never when the dictation flow does.
@MainActor
final class PermissionAdvisor {

    /// Injected so tests can drive every state; nil means "show no permission rows at all", which
    /// is what the state-machine tests want.
    var probe: (any PermissionProbe)?

    private(set) var advice: [(permission: Permission, advice: PermissionAdvice)] = []

    /// Recomputed on menu OPEN rather than polled: the user changes these in System Settings while
    /// the menu is CLOSED, so a value cached at launch is stale exactly when someone acts on it.
    func refresh() {
        guard let probe else { advice = []; return }
        advice = Permission.allCases.compactMap { permission in
            guard let entry = PermissionAdvice.forStatus(probe.status(of: permission),
                                                         of: permission) else { return nil }
            return (permission, entry)
        }
    }
}
