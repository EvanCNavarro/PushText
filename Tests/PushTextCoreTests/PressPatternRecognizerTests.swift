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

    @Test("Press and release round-trip to the plain events")
    func pressRelease() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
        #expect(recognizer.handle(.released, at: 0.1) == .hotkeyReleased)
    }

    @Test("Two quick taps produce a double press on the second")
    func twoQuickTaps() {
        var recognizer = PressPatternRecognizer()
        #expect(recognizer.handle(.pressed, at: 0) == .hotkeyPressed)
        #expect(recognizer.handle(.released, at: 0.08) == .hotkeyReleased)

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

    @Test("Releases always pass through unchanged, whatever the pattern")
    func releasesPassThrough() {
        var recognizer = PressPatternRecognizer()
        _ = recognizer.handle(.pressed, at: 0)
        #expect(recognizer.handle(.released, at: 0.05) == .hotkeyReleased)
        _ = recognizer.handle(.pressed, at: 0.1)
        #expect(recognizer.handle(.released, at: 0.15) == .hotkeyReleased)
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
