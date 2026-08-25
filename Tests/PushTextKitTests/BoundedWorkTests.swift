import Testing
import Foundation
@testable import PushTextKit

/// Bounding a call that can hang forever (#178).
@Suite("Bounded work")
struct BoundedWorkTests {

    @Test("Work that finishes returns its value")
    func fastWorkReturns() throws {
        let value = try BoundedWork.run("fast", timeout: 5) { 42 }
        #expect(value == 42)
    }

    /// The whole point. Without a deadline this is the call that took the CI job down for ten
    /// minutes at a time.
    @Test("Work that hangs throws instead of waiting forever")
    func hangingWorkTimesOut() {
        let started = ContinuousClock.now
        #expect(throws: BoundedWork.TimedOut.self) {
            try BoundedWork.run("a call that never returns", timeout: 0.3) {
                Thread.sleep(forTimeInterval: 30)
                return 0
            }
        }
        // It must give up NEAR the deadline. A timeout that still waits for the work to finish is
        // the bug wearing a different hat.
        #expect(started.duration(to: .now) < .seconds(5), "it waited for the hung work anyway")
    }

    @Test("The failure says what timed out, so a log reader knows")
    func errorNamesTheWork() {
        do {
            _ = try BoundedWork.run("the pasteboard", timeout: 0.2) {
                Thread.sleep(forTimeInterval: 10); return 0
            }
            Issue.record("expected a timeout")
        } catch let error as BoundedWork.TimedOut {
            #expect(error.description.contains("the pasteboard"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
