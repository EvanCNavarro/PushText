import Testing
import Foundation
@testable import PushText
import PushTextKit

/// A runtime failure outranks the probe (#136).
///
/// The event tap failing to arm IS observed evidence that Accessibility is not usable. The probe's
/// `AXIsProcessTrusted()` is a second-hand report of the same thing, and after a re-sign it can
/// disagree - the system lists an entry for a build that no longer exists. When the two disagree,
/// the thing that actually failed wins.
///
/// Before this, a tap failure produced a dead-end sentence in the menu: "Grant it in System Settings
/// > Privacy & Security > Accessibility, then relaunch PushText." No button, on a row that sat
/// directly above rows that had one.
@Suite("Permission advisor")
@MainActor
struct PermissionAdvisorTests {

    private struct StubProbe: PermissionProbe {
        var statuses: [Permission: PermissionStatus]
        func status(of permission: Permission) -> PermissionStatus {
            statuses[permission] ?? .granted
        }
    }

    @Test("Everything granted and nothing failed produces no rows at all")
    func silentWhenHealthy() {
        let advisor = PermissionAdvisor()
        advisor.probe = StubProbe(statuses: [:])
        advisor.refresh()
        #expect(advisor.advice.isEmpty)
    }

    /// THE case. The probe is happy; the tap is not. The user gets an actionable row rather than a
    /// silent app that does nothing when they hold the key.
    @Test("A runtime failure raises a row even when the probe says granted")
    func runtimeFailureOverridesTheProbe() {
        let advisor = PermissionAdvisor()
        advisor.probe = StubProbe(statuses: [.accessibility: .granted])
        advisor.runtimeFailures = [.accessibility]
        advisor.refresh()

        #expect(advisor.advice.count == 1)
        #expect(advisor.advice.first?.permission == .accessibility)
        #expect(advisor.advice.first?.advice.repairs == true,
                "a grant that failed in practice is a BROKEN one, so it offers the reset")
    }

    /// A failure must not invent a second row for a permission the probe is already reporting.
    @Test("A permission the probe already flags is not duplicated")
    func noDuplicateRows() {
        let advisor = PermissionAdvisor()
        advisor.probe = StubProbe(statuses: [.accessibility: .needsFirstGrant])
        advisor.runtimeFailures = [.accessibility]
        advisor.refresh()

        #expect(advisor.advice.count == 1)
    }

    /// Clearing the failure clears the row - otherwise the menu nags forever about a permission the
    /// user has since fixed.
    @Test("Resolving the failure removes the row")
    func failureClears() {
        let advisor = PermissionAdvisor()
        advisor.probe = StubProbe(statuses: [:])
        advisor.runtimeFailures = [.accessibility]
        advisor.refresh()
        #expect(advisor.advice.count == 1)

        advisor.runtimeFailures = []
        advisor.refresh()
        #expect(advisor.advice.isEmpty)
    }

    /// With no probe at all the advisor stays silent, which is what the state-machine tests want.
    @Test("No probe means no rows, failure or not")
    func noProbeNoRows() {
        let advisor = PermissionAdvisor()
        advisor.runtimeFailures = [.accessibility]
        advisor.refresh()
        #expect(advisor.advice.isEmpty)
    }
}
