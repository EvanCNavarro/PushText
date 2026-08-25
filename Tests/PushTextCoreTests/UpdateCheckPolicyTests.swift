import Testing
import Foundation
@testable import PushTextCore

/// When the passive update probe is allowed to run again (#170).
///
/// The dot was only ever right about releases that existed when the app STARTED, because the probe
/// ran once from `onLaunch` and nothing re-ran it. A menu-bar utility runs for days.
@Suite("Update check policy")
struct UpdateCheckPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The first check is always allowed")
    func firstCheckRuns() {
        #expect(UpdateCheckPolicy.shouldCheck(lastCompleted: nil, now: now, isChecking: false))
    }

    /// Opening the menu asks for a check, and the menu gets opened constantly. Without this the app
    /// hits the appcast every time the user glances at it.
    @Test("A check just done is not repeated")
    func quietPeriodSuppresses() {
        let recent = now.addingTimeInterval(-60)
        #expect(!UpdateCheckPolicy.shouldCheck(lastCompleted: recent, now: now, isChecking: false))
    }

    @Test("Once the quiet period has passed, it checks again")
    func staleCheckRuns() {
        let old = now.addingTimeInterval(-UpdateCheckPolicy.quietPeriod - 1)
        #expect(UpdateCheckPolicy.shouldCheck(lastCompleted: old, now: now, isChecking: false))
    }

    /// A second probe launched over a live one is how the availability state gets stranded on
    /// `.checking` - which renders as no dot at all.
    @Test("A check already in flight is never doubled up")
    func inFlightBlocks() {
        let ancient = now.addingTimeInterval(-100_000)
        #expect(!UpdateCheckPolicy.shouldCheck(lastCompleted: ancient, now: now, isChecking: true))
        #expect(!UpdateCheckPolicy.shouldCheck(lastCompleted: nil, now: now, isChecking: true))
    }

    /// The clock CAN go backwards - a timezone change, an NTP correction, a laptop waking with a
    /// bad RTC. Comparing elapsed time naively makes that arithmetic negative, which reads as "just
    /// checked" and disables the probe until real time catches up. On a big correction that is
    /// forever.
    @Test("A backwards clock does not disable the check")
    func backwardsClockStillChecks() {
        let future = now.addingTimeInterval(86_400)
        #expect(UpdateCheckPolicy.shouldCheck(lastCompleted: future, now: now, isChecking: false))
    }

    @Test("The intervals are sane rather than accidental")
    func intervalsAreSane() {
        #expect(UpdateCheckPolicy.quietPeriod >= 5 * 60, "hammering the appcast on every menu open")
        #expect(UpdateCheckPolicy.background >= UpdateCheckPolicy.quietPeriod)
        #expect(UpdateCheckPolicy.background <= 24 * 3600, "a day-old answer is barely an answer")
    }
}
