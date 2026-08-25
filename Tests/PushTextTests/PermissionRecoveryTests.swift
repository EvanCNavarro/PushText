import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Recovering after the user fixes a permission (#152).
///
/// Bobby granted Accessibility, and the menu still showed three NEEDS ATTENTION rows. The probe
/// disagreed with all of them - `microphone=granted accessibility=granted postEvent=granted`.
///
/// `runtimeFailures` was only ever INSERTED into. #136 made a runtime failure outrank the probe,
/// which is right while the failure is current and wrong once the user has fixed it. Nothing cleared
/// it, so the rows were permanent for the life of the process.
///
/// Clearing on "the probe now says granted" alone would be worse than the bug: the event tap is
/// still dead until something re-arms it, so the menu would report health while dictation stayed
/// broken. Recovery has to RETRY and clear only on success.
@Suite("Permission recovery")
@MainActor
struct PermissionRecoveryTests {

    private struct StubProbe: PermissionProbe {
        var statuses: [Permission: PermissionStatus]
        func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .granted }
    }

    private func model(probe: StubProbe) -> AppModel {
        let model = AppModel(engine: MockTranscriptionEngine())
        model.permissionProbe = probe
        return model
    }

    /// THE case. Granted since, retry works, row goes.
    @Test("A fixed permission clears once the retry succeeds")
    func fixedPermissionClears() {
        let model = model(probe: StubProbe(statuses: [.accessibility: .granted]))
        model.reportPermissionFailure(.accessibility)
        model.refreshPermissionAdvice()
        #expect(model.permissionAdvice.isEmpty == false, "precondition: the row is showing")

        model.retryPermissionFailures { _ in true }

        #expect(model.permissionAdvice.isEmpty, "the row survived a successful retry")
    }

    /// The dangerous direction. If the retry FAILS the row must stay, or the menu claims health the
    /// app does not have.
    @Test("A failed retry keeps the row, even though the probe says granted")
    func failedRetryKeepsTheRow() {
        let model = model(probe: StubProbe(statuses: [.accessibility: .granted]))
        model.reportPermissionFailure(.accessibility)

        model.retryPermissionFailures { _ in false }

        #expect(model.permissionAdvice.isEmpty == false,
                "cleared on a failed retry - the menu would say fine while dictation is broken")
    }

    /// No retry is attempted while the permission is genuinely still missing. Re-arming a tap that
    /// cannot work just fails noisily on every menu open.
    @Test("Nothing is retried while the probe still reports the permission missing")
    func noRetryWhileStillMissing() {
        let model = model(probe: StubProbe(statuses: [.accessibility: .needsFirstGrant]))
        model.reportPermissionFailure(.accessibility)

        var attempts = 0
        model.retryPermissionFailures { _ in attempts += 1; return true }

        #expect(attempts == 0)
        #expect(model.permissionAdvice.isEmpty == false)
    }

    /// Each permission is retried on its own - one succeeding must not clear another's row.
    ///
    /// BOTH probes say granted deliberately. An earlier version had the microphone probe report
    /// `needsFirstGrant`, so its row appeared from the PROBE whatever the recovery did - and a
    /// planted `removeAll()` sailed through. The row must depend on the runtime failure alone, or
    /// the assertion is measuring something else.
    @Test("Permissions recover independently")
    func recoveryIsPerPermission() {
        let model = model(probe: StubProbe(statuses: [.accessibility: .granted,
                                                      .microphone: .granted]))
        model.reportPermissionFailure(.accessibility)
        model.reportPermissionFailure(.microphone)

        // Only accessibility comes back working; the microphone retry still fails.
        model.retryPermissionFailures { $0 == .accessibility }

        let shown = model.permissionAdvice.map(\.permission)
        #expect(shown.contains(.accessibility) == false, "a working permission kept its row")
        #expect(shown.contains(.microphone),
                "a still-broken permission lost its row because another one recovered")
    }

    /// With nothing wrong, recovery does nothing at all.
    @Test("A healthy app retries nothing")
    func healthyAppRetriesNothing() {
        let model = model(probe: StubProbe(statuses: [:]))
        var attempts = 0
        model.retryPermissionFailures { _ in attempts += 1; return true }
        #expect(attempts == 0)
        #expect(model.permissionAdvice.isEmpty)
    }
}
