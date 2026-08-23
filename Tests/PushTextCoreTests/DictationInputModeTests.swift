import Testing
import Foundation
@testable import PushTextCore

/// The two ways to start an utterance, and the two ways to end one (#46).
///
/// Hold-to-talk is the existing fast path and must not regress. Latched mode exists because holding
/// a modifier for a long dictation is uncomfortable and makes the key unusable for anything else
/// while held. Cancel exists because today an utterance you regret is injected into your document
/// no matter what - there is no way to abandon one.
///
/// These are tested here, in Core, precisely because the timing and the mode rules are product
/// decisions. Buried in an event-tap callback they would be untestable and would drift.
@Suite("Dictation input modes")
struct DictationInputModeTests {

    // MARK: - Hold mode is unchanged

    @Test("Hold: press starts, release ends and transcribes")
    func holdRoundTrip() {
        var machine = DictationMachine()
        machine.apply(.hotkeyPressed)
        #expect(machine.inputMode == .hold)
        machine.apply(.audioStarted)
        #expect(machine.state == .recording)

        machine.apply(.hotkeyReleased)
        #expect(machine.state == .transcribing)
    }

    // MARK: - Latched mode

    @Test("Latched: a double press starts recording that survives the key release")
    func latchedSurvivesRelease() {
        var machine = DictationMachine()
        machine.apply(.hotkeyDoublePressed)
        #expect(machine.inputMode == .latched)
        machine.apply(.audioStarted)
        #expect(machine.state == .recording)

        // THE point of the mode. In hold mode this same event ends the utterance.
        let changed = machine.apply(.hotkeyReleased)
        #expect(changed == false, "a latched utterance must ignore the key release")
        #expect(machine.state == .recording)
    }

    @Test("Latched: pressing again ends the utterance and transcribes")
    func latchedPressAgainEnds() {
        var machine = DictationMachine(state: .recording)
        machine.startLatchedForTesting()

        machine.apply(.hotkeyPressed)

        #expect(machine.state == .transcribing)
    }

    @Test("Latched: releasing the key that ended it does not start a new utterance")
    func latchedEndingReleaseIsInert() {
        var machine = DictationMachine(state: .recording)
        machine.startLatchedForTesting()
        machine.apply(.hotkeyPressed)
        #expect(machine.state == .transcribing)

        let changed = machine.apply(.hotkeyReleased)
        #expect(changed == false, "the release after the ending press must be ignored")
        #expect(machine.state == .transcribing)
    }

    /// Arming is the window between key-down and the engine being ready. A latched utterance
    /// released during it must NOT be discarded the way a hold-mode tap is - the user has already
    /// committed to recording.
    @Test("Latched: a release during arming does not cancel the utterance")
    func latchedReleaseDuringArmingIsIgnored() {
        var machine = DictationMachine()
        machine.apply(.hotkeyDoublePressed)
        #expect(machine.state == .arming)

        let changed = machine.apply(.hotkeyReleased)
        #expect(changed == false)
        #expect(machine.state == .arming)
    }

    @Test("Hold: a release during arming still discards, because it was too short to be speech")
    func holdReleaseDuringArmingDiscards() {
        var machine = DictationMachine()
        machine.apply(.hotkeyPressed)
        machine.apply(.hotkeyReleased)
        #expect(machine.state == .idle)
    }

    // MARK: - End and Cancel are different outcomes

    @Test("End transcribes, in either mode")
    func endTranscribes() {
        for start in [DictationEvent.hotkeyPressed, .hotkeyDoublePressed] {
            var machine = DictationMachine()
            machine.apply(start)
            machine.apply(.audioStarted)

            machine.apply(.endRequested)

            #expect(machine.state == .transcribing, "end failed for \(start)")
        }
    }

    /// The one that does not exist today. Cancel must reach `.idle` WITHOUT passing through
    /// `.transcribing` - anything that reaches transcribing eventually injects, and the whole point
    /// of cancel is that nothing is typed.
    @Test("Cancel returns to idle without transcribing or injecting")
    func cancelDiscards() {
        for start in [DictationEvent.hotkeyPressed, .hotkeyDoublePressed] {
            var machine = DictationMachine()
            machine.apply(start)
            machine.apply(.audioStarted)

            machine.apply(.cancelRequested)

            #expect(machine.state == .idle, "cancel failed for \(start)")
        }
    }

    @Test("Cancel works while still arming, before any audio has been captured")
    func cancelDuringArming() {
        var machine = DictationMachine()
        machine.apply(.hotkeyDoublePressed)
        #expect(machine.state == .arming)

        machine.apply(.cancelRequested)

        #expect(machine.state == .idle)
    }

    /// Cancel is deliberate, not a failure. Routing it through `.failed` would show the user an
    /// error for doing exactly what they intended.
    @Test("Cancel is not a failure state")
    func cancelIsNotAFailure() {
        var machine = DictationMachine()
        machine.apply(.hotkeyDoublePressed)
        machine.apply(.audioStarted)
        machine.apply(.cancelRequested)

        if case .failed = machine.state {
            Issue.record("cancel must not produce a failure state")
        }
    }

    @Test("Cancel after the utterance already ended is ignored, not a way to un-inject")
    func cancelAfterEndIsIgnored() {
        var machine = DictationMachine(state: .injecting)

        let changed = machine.apply(.cancelRequested)

        #expect(changed == false)
        #expect(machine.state == .injecting)
    }

    // MARK: - Mode resets

    @Test("A new hold utterance after a latched one is not still latched")
    func modeResetsBetweenUtterances() {
        var machine = DictationMachine()
        machine.apply(.hotkeyDoublePressed)
        machine.apply(.audioStarted)
        machine.apply(.endRequested)
        machine.apply(.transcriptFinalized("hello"))
        machine.apply(.cleanupFinished("hello"))
        machine.apply(.injectionFinished)
        #expect(machine.state == .idle)

        machine.apply(.hotkeyPressed)
        #expect(machine.inputMode == .hold, "mode leaked from the previous utterance")
        machine.apply(.audioStarted)
        machine.apply(.hotkeyReleased)
        #expect(machine.state == .transcribing)
    }

    @Test("Retrying after a failure starts in hold mode, not whatever the failed one used")
    func modeResetsAfterFailure() {
        var machine = DictationMachine(state: .failed(.noSpeechDetected))
        machine.startLatchedForTesting()

        machine.apply(.hotkeyPressed)

        #expect(machine.state == .arming)
        #expect(machine.inputMode == .hold)
    }
}
