import Testing
@testable import PushTextCore

/// `#expect` expands into a closure that receives the subject immutably, so a `mutating` call
/// cannot be written inline inside the macro. Every transition here is applied to a local first
/// and the returned "did it change" flag is asserted separately.
@Suite("DictationMachine transitions")
struct DictationStateTests {

    @Test("A complete utterance walks idle -> arming -> recording -> ... -> idle")
    func happyPath() {
        var machine = DictationMachine()
        #expect(machine.state == .idle)

        var changed = machine.apply(.hotkeyPressed)
        #expect(changed)
        #expect(machine.state == .arming)

        changed = machine.apply(.audioStarted)
        #expect(changed)
        #expect(machine.state == .recording)
        #expect(machine.isCapturing)

        changed = machine.apply(.hotkeyReleased)
        #expect(changed)
        #expect(machine.state == .transcribing)
        #expect(!machine.isCapturing)

        changed = machine.apply(.transcriptFinalized("hello world"))
        #expect(changed)
        #expect(machine.state == .cleaning)

        changed = machine.apply(.cleanupFinished("Hello, world."))
        #expect(changed)
        #expect(machine.state == .injecting)

        changed = machine.apply(.injectionFinished)
        #expect(changed)
        #expect(machine.state == .idle)
        #expect(machine.isTerminal)
    }

    @Test("Releasing during arming returns to idle without reporting a failure")
    func tapTooShort() {
        var machine = DictationMachine(state: .arming)
        let changed = machine.apply(.hotkeyReleased)
        #expect(changed)
        #expect(machine.state == .idle)
    }

    @Test("An empty or whitespace-only transcript is noSpeechDetected, not an empty injection",
          arguments: ["", "   ", "\n\t "])
    func emptyTranscriptFails(text: String) {
        var machine = DictationMachine(state: .transcribing)
        machine.apply(.transcriptFinalized(text))
        #expect(machine.state == .failed(.noSpeechDetected))
    }

    @Test("A transcript that is only meaningful after trimming still proceeds")
    func paddedTranscriptProceeds() {
        var machine = DictationMachine(state: .transcribing)
        machine.apply(.transcriptFinalized("  ship it  "))
        #expect(machine.state == .cleaning)
    }

    /// The mic-stuck-open case. If the hotkey release is never observed — the documented
    /// consequence of using the union `maskAlternate` instead of the device-dependent right-side
    /// bit — nothing else in the system ends the utterance.
    /// The watchdog exists to stop a STUCK MICROPHONE, and a stuck microphone has still been
    /// recording someone's voice. Ending the capture and KEEPING the words is the whole point of the
    /// distinction (#197).
    ///
    /// This test used to assert `.failed(.cancelled)` - it codified the data loss. Bobby: *"i just
    /// recorded for a long time and it seems like it just died out? and i lost all of that
    /// information i was talking on."* Everything he had said was thrown away by a timer.
    @Test("The watchdog ends a long capture by TRANSCRIBING it, not discarding it")
    func watchdogFinishesLongCapture() {
        var machine = DictationMachine(state: .recording)
        #expect(machine.isCapturing)
        let changed = machine.apply(.watchdogExpired)
        #expect(changed)
        #expect(machine.state == .transcribing,
                "the words were thrown away - this is the bug the user hit")
        #expect(!machine.isCapturing)
    }

    /// `.arming` is different and must STAY a cancel: the microphone never opened, so there is
    /// nothing to keep. Transcribing an utterance that captured nothing would inject an empty
    /// string over whatever the user was doing.
    @Test("The watchdog cancels while still arming, because nothing was captured")
    func watchdogCancelsWhileArming() {
        var machine = DictationMachine(state: .arming)
        let changed = machine.apply(.watchdogExpired)
        #expect(changed)
        #expect(machine.state == .failed(.cancelled))
        #expect(!machine.isCapturing)
    }

    @Test("The watchdog is inert once capture has ended")
    func watchdogIgnoredAfterCapture() {
        var machine = DictationMachine(state: .transcribing)
        let changed = machine.apply(.watchdogExpired)
        #expect(!changed)
        #expect(machine.state == .transcribing)
    }

    @Test("Duplicate key-down events from the event tap are ignored, not stacked")
    func duplicatePressIgnored() {
        var machine = DictationMachine()
        let first = machine.apply(.hotkeyPressed)
        let second = machine.apply(.hotkeyPressed)
        #expect(first)
        #expect(!second)
        #expect(machine.state == .arming)
    }

    @Test("A failure from any active state is terminal")
    func failureFromActiveState() {
        var machine = DictationMachine(state: .recording)
        let changed = machine.apply(.failure(.permissionDenied))
        #expect(changed)
        #expect(machine.state == .failed(.permissionDenied))
        #expect(machine.isTerminal)
    }

    @Test("A failure while idle is ignored — there is no utterance to fail")
    func failureWhileIdleIgnored() {
        var machine = DictationMachine()
        let changed = machine.apply(.failure(.transcriptionFailed))
        #expect(!changed)
        #expect(machine.state == .idle)
    }

    @Test("Out-of-order events do not advance the machine")
    func outOfOrderIgnored() {
        var machine = DictationMachine()
        let a = machine.apply(.injectionFinished)
        let b = machine.apply(.transcriptFinalized("nope"))
        let c = machine.apply(.audioStarted)
        #expect(!a)
        #expect(!b)
        #expect(!c)
        #expect(machine.state == .idle)
    }

    /// A failed utterance must not brick the app.
    ///
    /// Observed in the field before this test existed: the first utterance failed with
    /// `permissionDenied`, and every subsequent key press produced `hotkeyPressed` edges with NO
    /// state change, because `.failed` had no outgoing transition. The app looked dead and the only
    /// cure was relaunching it. A dictation key that stops working after one error is worse than one
    /// that errors every time, because the user cannot tell which state they are in.
    @Test("A new press recovers from a failed utterance instead of staying stuck")
    func pressRecoversFromFailure() {
        for failure in [DictationFailure.permissionDenied,
                        .noSpeechDetected,
                        .transcriptionFailed,
                        .injectionFailed,
                        .cancelled] {
            var machine = DictationMachine(state: .failed(failure))
            let changed = machine.apply(.hotkeyPressed)
            #expect(changed, "no way out of .failed")
            #expect(machine.state == .arming)
        }
    }

    @Test("A release in the failed state is ignored rather than starting an utterance")
    func releaseInFailedIsIgnored() {
        var machine = DictationMachine(state: .failed(.permissionDenied))
        let changed = machine.apply(.hotkeyReleased)
        #expect(changed == false)
        #expect(machine.state == .failed(.permissionDenied))
    }
}
