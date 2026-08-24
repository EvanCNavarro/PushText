import Testing
import Foundation
@testable import PushTextKit

/// Clearing this app's stale TCC rows (#136), ported from TermTile's `TCCPermissionRepairer`.
///
/// The runner is injected because the real one shells out to `/usr/bin/tccutil`, and a test that
/// actually ran it would destroy the developer's own grants.
@Suite("Permission repairer")
@MainActor
struct PermissionRepairerTests {

    private final class Recorder {
        var calls: [(String, [String])] = []
        var exitCode: Int32 = 0
        func run(_ executable: String, _ arguments: [String]) -> Int32 {
            calls.append((executable, arguments))
            return exitCode
        }
    }

    /// THE safety property. `tccutil reset Accessibility` with no bundle id clears the grant for
    /// EVERY app on the machine. The id is not a nicety, it is the difference between repairing
    /// this app and vandalising someone's Mac.
    @Test("Every reset is scoped to this app's bundle id")
    func resetIsAlwaysBundleScoped() {
        let recorder = Recorder()
        let repairer = TCCPermissionRepairer(bundleID: "dev.ecn.apps.pushtext", runner: recorder.run)

        repairer.reset([.accessibility, .postEvent, .microphone])

        #expect(recorder.calls.count == 3)
        for (executable, arguments) in recorder.calls {
            #expect(executable == "/usr/bin/tccutil")
            #expect(arguments.first == "reset")
            #expect(arguments.last == "dev.ecn.apps.pushtext",
                    "unscoped reset would clear every app on the machine: \(arguments)")
            #expect(arguments.count == 3)
        }
    }

    /// The TCC service names are not the same strings as the UI labels, and PostEvent is its own
    /// service despite sharing one toggle with Accessibility in System Settings.
    @Test("Each permission maps to its real TCC service name")
    func serviceNamesAreTheTCCOnes() {
        let recorder = Recorder()
        let repairer = TCCPermissionRepairer(bundleID: "x", runner: recorder.run)

        repairer.reset([.accessibility, .postEvent, .microphone])

        #expect(recorder.calls.map { $0.1[1] } == ["Accessibility", "PostEvent", "Microphone"])
    }

    /// A failed reset must be visible. Reporting success regardless would send the user to Settings
    /// expecting a clean slate that is still stale.
    @Test("A non-zero exit is reported as failure, not swallowed")
    func failureIsReported() {
        let recorder = Recorder()
        recorder.exitCode = 1
        let repairer = TCCPermissionRepairer(bundleID: "x", runner: recorder.run)

        let reports = repairer.reset([.accessibility])

        #expect(reports.count == 1)
        #expect(reports[0].succeeded == false)
        #expect(reports[0].exitCode == 1)
    }

    @Test("A clean exit reports success")
    func successIsReported() {
        let recorder = Recorder()
        let repairer = TCCPermissionRepairer(bundleID: "x", runner: recorder.run)
        let reports = repairer.reset([.microphone])
        #expect(reports.allSatisfy { $0.succeeded })
    }

    /// Resetting nothing must run nothing. An empty scope list reaching a shell-out is how a bare
    /// `tccutil reset` gets issued by accident.
    @Test("An empty scope list runs no process at all")
    func emptyScopeRunsNothing() {
        let recorder = Recorder()
        let repairer = TCCPermissionRepairer(bundleID: "x", runner: recorder.run)
        #expect(repairer.reset([]).isEmpty)
        #expect(recorder.calls.isEmpty)
    }
}
