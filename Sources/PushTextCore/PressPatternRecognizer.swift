import Foundation

/// Turns raw key edges into dictation events, recognising the double press that starts a latched
/// utterance (#46).
///
/// **Why this is a separate type in Core.** The thresholds below are product decisions - how fast is
/// a "double", how long a press can be and still count as a tap - and inside an event-tap callback
/// they would be untestable and would drift. Here they are pure, and the boundaries are asserted at
/// exact values rather than by sleeping.
///
/// **Time is a parameter, not a clock read.** Callers pass a monotonic timestamp. That makes the
/// windows testable, and it means a caller who mistakenly passes a wall clock cannot produce a
/// spurious latch when the clock steps backwards - going backwards is treated as "not a double".
public struct PressPatternRecognizer: Sendable {

    /// Longest a press can last and still count as a TAP rather than a dictation.
    ///
    /// This is what lets hold-to-talk and latching coexist: a long press is someone dictating, so a
    /// press shortly after it must not be read as the second half of a double. Without it, every
    /// dictation followed by a quick correction would silently latch.
    public let tapMaximumDuration: TimeInterval

    /// Longest gap between the first tap's RELEASE and the second tap's PRESS.
    ///
    /// Measured from the release rather than the press, so a slow first tap does not eat the budget
    /// the user has for the second one.
    public let doublePressWindow: TimeInterval

    private var pressStartedAt: TimeInterval?
    private var lastTapReleasedAt: TimeInterval?
    /// True between emitting a double press and its release, so the release that ENDS the double
    /// cannot arm another one. Without it a three-tap stutter - which real fingers produce - would
    /// latch, unlatch and relatch.
    private var justDoublePressed = false

    public init(tapMaximumDuration: TimeInterval = 0.3, doublePressWindow: TimeInterval = 0.4) {
        self.tapMaximumDuration = tapMaximumDuration
        self.doublePressWindow = doublePressWindow
    }

    /// Maps one edge to the event the machine should receive.
    public mutating func handle(_ edge: HotkeyEdge, at time: TimeInterval) -> DictationEvent {
        switch edge {
        case .pressed:
            return handlePress(at: time)
        case .released:
            return handleRelease(at: time)
        }
    }

    private mutating func handlePress(at time: TimeInterval) -> DictationEvent {
        defer { pressStartedAt = time }

        guard let lastTap = lastTapReleasedAt else { return .hotkeyPressed }
        lastTapReleasedAt = nil

        // `time >= lastTap` rejects a backwards clock rather than trusting the subtraction.
        guard time >= lastTap, time - lastTap <= doublePressWindow else { return .hotkeyPressed }

        justDoublePressed = true
        return .hotkeyDoublePressed
    }

    private mutating func handleRelease(at time: TimeInterval) -> DictationEvent {
        defer {
            pressStartedAt = nil
            justDoublePressed = false
        }

        guard !justDoublePressed, let start = pressStartedAt else {
            lastTapReleasedAt = nil
            return .hotkeyReleased
        }

        let wasTap = time >= start && time - start <= tapMaximumDuration
        lastTapReleasedAt = wasTap ? time : nil
        // Tell the machine WHICH it was. It already computed this to arm the double-press window and
        // then discarded it, which left the machine deciding "tap or dictation?" from whether
        // capture had started - a race it loses by about 4 ms (#105).
        return wasTap ? .hotkeyTapReleased : .hotkeyReleased
    }
}
