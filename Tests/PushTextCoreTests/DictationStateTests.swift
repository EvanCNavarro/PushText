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
    @Test("The watchdog ends a capture that the hotkey never closed",
          arguments: [DictationState.arming, .recording])
    func watchdogClosesStuckCapture(from state: DictationState) {
        var machine = DictationMachine(state: state)
        #expect(machine.isCapturing)
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
}
