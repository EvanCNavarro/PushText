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

    /// Permissions a subsystem ACTUALLY failed on, which outranks the probe (#136).
    ///
    /// The event tap failing to arm is observed evidence that Accessibility is unusable;
    /// `AXIsProcessTrusted()` is a second-hand report of the same thing, and after a re-sign the two
    /// disagree - the system lists an entry for a build that no longer exists, so the probe says
    /// granted while nothing works. When they disagree, the thing that actually failed wins, and it
    /// is treated as a BROKEN grant because that is exactly what it is.
    var runtimeFailures: Set<Permission> = []

    private(set) var advice: [(permission: Permission, advice: PermissionAdvice)] = []

    /// Recomputed on menu OPEN rather than polled: the user changes these in System Settings while
    /// the menu is CLOSED, so a value cached at launch is stale exactly when someone acts on it.
    func refresh() {
        guard let probe else { advice = []; return }
        advice = Permission.allCases.compactMap { permission in
            // A failure downgrades the reading rather than adding a second row, so a permission the
            // probe already flags is never duplicated.
            let status = runtimeFailures.contains(permission) ? .grantBroken
                                                              : probe.status(of: permission)
            guard let entry = PermissionAdvice.forStatus(status, of: permission) else { return nil }
            return (permission, entry)
        }
    }
}
