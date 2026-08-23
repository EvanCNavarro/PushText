import Testing
import Foundation
@testable import PushTextCore

/// Turns raw key edges into the events the machine understands, including the double press that
/// starts a latched utterance (#46).
///
/// Timestamps are passed in rather than read from a clock, so the thresholds are testable at exact
/// boundaries instead of by sleeping. A recogniser that can only be tested by waiting is one whose
/// edge cases never get tested.
@Suite("PressPatternRecognizer")
struct PressPatternRecognizerTests {

    /// A single press-and-hold is the fast path and must stay a plain press.
    @Test("A lone press is an ordinary press, not a double")
    func lonePress() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
    }

    @Test("A press and a SHORT release round-trip to press and tap-release")
    func pressRelease() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
        // 0.1 s is inside `tapMaximumDuration`, so this is a tap and the machine must be told so
        // rather than left to infer it from whether capture had started (#105).
        #expect(recognizer.handle(.released, at: 0.1) == .hotkeyTapReleased)
    }

    @Test("A press held longer than a tap round-trips to a plain release")
    func longPressRelease() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
        #expect(recognizer.handle(.released, at: 1.0) == .hotkeyReleased)
    }

    @Test("Two quick taps produce a double press on the second")
    func twoQuickTaps() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
        #expect(recognizer.handle(.released, at: 0.08) == .hotkeyTapReleased)

        #expect(recognizer.handle(.pressed, at: 0.20) == .hotkeyDoublePressed)
    }

    /// The boundary, asserted exactly rather than "about". Off-by-one on a timing window is the
    /// classic way a gesture becomes unreliable in the hand and untestable in CI.
    @Test("A second tap exactly at the window still counts")
    func atTheWindow() {
        var recognizer = PressPatternRecognizer(doublePressWindow: 0.4)
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 0.05)

        #expect(recognizer.handle(.pressed, at: 0.45) == .hotkeyDoublePressed)
    }

    @Test("A second tap past the window is a fresh press, not a double")
    func pastTheWindow() {
        var recognizer = PressPatternRecognizer(doublePressWindow: 0.4)
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 0.05)

        #expect(recognizer.handle(.pressed, at: 0.46) == .hotkeyPressed)
    }

    /// The case that makes hold-to-talk and latching coexist. A long press is a HOLD - the user
    /// dictated. A press soon after must not be read as the second half of a double, or every
    /// dictation followed by a quick correction would silently latch.
    @Test("A press following a HOLD is not a double press")
    func holdThenPressIsNotDouble() {
        var recognizer = PressPatternRecognizer(tapMaximumDuration: 0.3)
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 2.0)   // held for two seconds: a dictation

        #expect(recognizer.handle(.pressed, at: 2.1) == .hotkeyPressed)
    }

    @Test("A press exactly at the tap-duration limit still counts as a tap")
    func tapDurationBoundary() {
        var recognizer = PressPatternRecognizer(tapMaximumDuration: 0.3, doublePressWindow: 0.4)
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 0.3)

        #expect(recognizer.handle(.pressed, at: 0.5) == .hotkeyDoublePressed)
    }

    /// Otherwise one double press would arm the next one, and a three-tap stutter - which real
    /// fingers produce - would latch, unlatch and relatch unpredictably.
    @Test("A double press consumes the history, so a third tap starts fresh")
    func doubleConsumesHistory() {
        var recognizer = PressPatternRecognizer()
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 0.05)
        #expect(recognizer.handle(.pressed, at: 0.20) == .hotkeyDoublePressed)
        _ = recognizer.handle(.released, at: 0.25)

        #expect(recognizer.handle(.pressed, at: 0.40) == .hotkeyPressed)
    }

    /// The intent of this test is that a release is NEVER swallowed - every one produces an event.
    /// What changed in #105 is WHICH event: a tap now says so. Kept rather than deleted, because
    /// "no release goes missing" is still the property worth pinning.
    @Test("Every release produces an event, and a tap says it was a tap")
    func releasesPassThrough() {
        var recognizer = PressPatternRecognizer()
        _ = recognizer.handle(.pressed, at: 0)
        #expect(recognizer.handle(.released, at: 0.05) == .hotkeyTapReleased)
        // This press is within the double-press window of the release above, so it IS a double
        // press - and the release that closes a double press is deliberately plain, because
        // `justDoublePressed` suppresses tap handling so a three-tap stutter cannot relatch.
        #expect(recognizer.handle(.pressed, at: 0.1) == .hotkeyDoublePressed)
        #expect(recognizer.handle(.released, at: 0.15) == .hotkeyReleased)
        // And a genuine hold is still a plain release, so the new event is a real distinction
        // rather than a rename of every release.
        _ = recognizer.handle(.pressed, at: 2.0)
        #expect(recognizer.handle(.released, at: 3.0) == .hotkeyReleased)
    }

    /// A tap, then a long gap, then a tap, then a quick tap: only the LAST pair is close enough.
    @Test("Only the most recent tap arms the double press")
    func onlyRecentTapCounts() {
        var recognizer = PressPatternRecognizer(doublePressWindow: 0.4)
        _ = recognizer.handle(.pressed, at: 0)
        _ = recognizer.handle(.released, at: 0.05)

        #expect(recognizer.handle(.pressed, at: 5.0) == .hotkeyPressed)
        _ = recognizer.handle(.released, at: 5.05)

        #expect(recognizer.handle(.pressed, at: 5.2) == .hotkeyDoublePressed)
    }

    /// Time going backwards is not hypothetical if a caller ever passes a wall clock instead of a
    /// monotonic one. It must not produce a spurious latch.
    ///
    /// The backwards step is deliberately SMALLER than the window (0.15s back, window 0.4s). An
    /// earlier version of this test stepped back 1.05s, which is outside the window in either
    /// direction - so it passed on an implementation using `abs()` and proved nothing. Caught by
    /// planting exactly that.
    @Test("A backwards timestamp inside the window does not produce a double press")
    func backwardsTimeIsSafe() {
        var recognizer = PressPatternRecognizer(doublePressWindow: 0.4)
        _ = recognizer.handle(.pressed, at: 10.0)
        _ = recognizer.handle(.released, at: 10.05)

        #expect(recognizer.handle(.pressed, at: 9.9) == .hotkeyPressed)
    }
}
