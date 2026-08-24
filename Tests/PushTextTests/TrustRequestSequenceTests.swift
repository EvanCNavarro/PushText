import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// One thing per press, in the order macOS expects (#148).
///
/// Bobby, seeing the system dialog and System Settings appear together: *"this window and the system
/// one both popped up? seems redundant, or should be ordered differently or sequentially."*
///
/// Two facts from the platform decide this:
///
/// 1. The prompt carries its OWN "Open System Settings" button, so opening the pane as well is a
///    second copy of an affordance the dialog already provides.
/// 2. **The prompt fires once.** After the user answers - Deny included - macOS never shows it
///    again for that app. From then on Settings is the only route, so the button has to become the
///    Settings button rather than a no-op.
@Suite("Trust request sequence")
@MainActor
struct TrustRequestSequenceTests {

    private final class Spy: PermissionRepairing {
        var order: [String] = []
        var asked: Set<Permission> = []
        func reset(_ permissions: [Permission]) -> [PermissionRepairReport] {
            order.append("reset")
            return permissions.map { PermissionRepairReport(permission: $0, exitCode: 0) }
        }
    }

    private func actions(_ spy: Spy, alreadyAsked: Set<Permission> = []) -> AppActions {
        spy.asked = alreadyAsked
        return AppActions(repairer: spy,
                          requestAccessibilityTrust: { spy.order.append("prompt") },
                          openURL: { _ in spy.order.append("open") },
                          hasRequestedTrust: { spy.asked.contains($0) },
                          recordRequestedTrust: { spy.asked.insert($0); spy.order.append("record") })
    }

    /// FIRST press: prompt, and nothing else. The dialog's own button takes it from there.
    @Test("The first press prompts and does NOT open Settings as well")
    func firstPressOnlyPrompts() {
        let spy = Spy()
        let advice = PermissionAdvice.forStatus(.needsFirstGrant, of: .accessibility)!
        actions(spy).resolvePermission(advice)

        #expect(spy.order.contains("prompt"))
        #expect(spy.order.contains("open") == false,
                "the pane opened alongside the dialog: \(spy.order)")
    }

    /// SECOND press: macOS will not show the prompt again, so a press that only prompted would do
    /// visibly nothing. Settings is the only remaining route.
    @Test("Once asked, a later press opens Settings instead of prompting into the void")
    func laterPressOpensSettings() {
        let spy = Spy()
        let advice = PermissionAdvice.forStatus(.needsFirstGrant, of: .accessibility)!
        actions(spy, alreadyAsked: [.accessibility]).resolvePermission(advice)

        #expect(spy.order == ["open"], "got \(spy.order)")
    }

    /// The asking must be REMEMBERED, or every press repeats the first one forever.
    @Test("Asking is recorded, so the next press behaves differently")
    func askingIsRemembered() {
        let spy = Spy()
        let advice = PermissionAdvice.forStatus(.needsFirstGrant, of: .accessibility)!
        actions(spy).resolvePermission(advice)
        #expect(spy.asked.contains(.accessibility))
    }

    /// A broken grant still clears the stale row first, then asks - and still does not double up.
    @Test("A broken grant resets, then prompts, and stops there")
    func brokenGrantResetsThenPrompts() {
        let spy = Spy()
        let advice = PermissionAdvice.forStatus(.grantBroken, of: .accessibility)!
        actions(spy).resolvePermission(advice)

        // record BEFORE prompt, deliberately: if the app died between the two, a fact recorded
        // afterwards would be lost and the next press would ask for a dialog macOS will never show.
        #expect(spy.order == ["reset", "record", "prompt"], "got \(spy.order)")
        #expect(spy.order.contains("open") == false)
    }

    /// The microphone is untouched by any of this: its own prompt, no pane, no trust request.
    @Test("The microphone still prompts for itself alone")
    func microphoneUnaffected() {
        let spy = Spy()
        let advice = PermissionAdvice.forStatus(.needsFirstGrant, of: .microphone)!
        actions(spy).resolvePermission(advice)
        #expect(spy.order.isEmpty)
    }
}
