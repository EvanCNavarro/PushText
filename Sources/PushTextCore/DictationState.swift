import Foundation

/// The lifecycle of a single dictation utterance.
///
/// Pure data: no timers, no audio, no OS. `DictationMachine` owns the legal transitions so the
/// shell and the adapters cannot invent their own. Modelled as an explicit machine rather than a
/// pile of booleans because the failure that matters most here is a *stuck* state — a hotkey
/// release that never lands leaves the microphone open (see PLAN.md §2.2, the right-modifier
/// device-flag trap), and a stuck state is only detectable if there is a state to inspect.
public enum DictationState: Equatable, Sendable {
    /// Nothing happening. The hotkey is up.
    case idle
    /// Hotkey down. Audio engine starting, LLM prewarming. Not yet capturing speech.
    ///
    /// This phase exists to buy latency: prewarming the language model on key-down gives us the
    /// user's entire speech duration for free, which is the single largest win available and the
    /// main reason cleanup runs in-process rather than over HTTP (PLAN.md §2.1).
    case arming
    /// Capturing audio and streaming it to the transcription engine.
    case recording
    /// Hotkey released. Draining the last audio and waiting for the final transcript.
    case transcribing
    /// Optional LLM polish pass. Skippable, and skipped silently on any failure.
    case cleaning
    /// Writing text into the frontmost app.
    case injecting
    /// Terminal for this utterance; carries why it ended badly.
    case failed(DictationFailure)
}

/// Why an utterance ended without text being injected.
///
/// Deliberately coarse. The user does not need nine kinds of bad news from a dictation key — the
/// product's job is to fail quietly and let them try again.
public enum DictationFailure: Equatable, Sendable {
    /// Microphone, Accessibility, or PostEvent permission is missing.
    case permissionDenied
    /// The transcription engine produced nothing usable.
    case noSpeechDetected
    /// The engine errored, or its result stream stalled past the timeout.
    ///
    /// The stall case is not theoretical: VoiceInk ships a `max(20, duration * 4 + 10)`s timeout
    /// on `transcriber.results` because the stream hangs in the field (docs/research/01 §7).
    case transcriptionFailed
    /// Text was produced but could not be written into the frontmost app.
    case injectionFailed
    /// The user let go before saying anything, or cancelled.
    case cancelled
}

/// Things that happen to a dictation, from outside.
public enum DictationEvent: Equatable, Sendable {
    case hotkeyPressed
    case hotkeyReleased
    case audioStarted
    case transcriptFinalized(String)
    case cleanupFinished(String)
    case injectionFinished
    case failure(DictationFailure)
    /// Panic path: the hotkey release was never observed and the watchdog fired.
    ///
    /// Real risk, not defensive coding — `CGEventFlags.maskAlternate` is a union mask, so with the
    /// wrong flag handling a left-Option hold makes the right-Option release invisible and the mic
    /// stays open (docs/research/03, docs/research/04 §1).
    case watchdogExpired
}

/// The legal transitions. Anything not listed here is ignored, and ignoring is deliberate:
/// duplicate key-down events from an event tap are normal, not exceptional.
public struct DictationMachine: Sendable {
    public private(set) var state: DictationState

    public init(state: DictationState = .idle) {
        self.state = state
    }

    /// Applies an event. Returns `true` if the state actually changed.
    @discardableResult
    public mutating func apply(_ event: DictationEvent) -> Bool {
        let next = Self.transition(from: state, on: event)
        guard let next, next != state else { return false }
        state = next
        return true
    }

    /// Pure transition function — the whole machine, in one place, testable without a machine.
    public static func transition(from state: DictationState, on event: DictationEvent) -> DictationState? {
        // Split from the main table purely to keep this function within the complexity limit; the
        // rules themselves stay in one place to read top to bottom.
        if let recovery = recoveryTransition(from: state, on: event) { return recovery }
        return progressTransition(from: state, on: event)
    }

    /// Ends an utterance: failures, the watchdog, and retrying after a failure.
    private static func recoveryTransition(
        from state: DictationState,
        on event: DictationEvent
    ) -> DictationState? {
        switch (state, event) {
        // The watchdog only means anything while the mic could be open.
        case (.arming, .watchdogExpired), (.recording, .watchdogExpired):
            return .failed(.cancelled)

        // A new press RETRIES. Without this, `.failed` is a dead end and one bad utterance disables
        // dictation until the app is relaunched - observed in the field: a permissionDenied failure
        // left every subsequent key press producing edges with no state change, so the app looked
        // dead rather than broken-once. A key that silently stops working is worse than one that
        // fails every time, because the user cannot tell which state they are in.
        case (.failed, .hotkeyPressed):
            return .arming

        case (_, .failure(let reason)):
            return state == .idle ? nil : .failed(reason)

        default:
            return nil
        }
    }

    /// Moves an utterance forward through its happy path.
    private static func progressTransition(
        from state: DictationState,
        on event: DictationEvent
    ) -> DictationState? {
        switch (state, event) {
        case (.idle, .hotkeyPressed):
            return .arming
        case (.arming, .audioStarted):
            return .recording

        // Released during arming: too short to be speech. Not a failure worth reporting.
        case (.arming, .hotkeyReleased):
            return .idle
        case (.recording, .hotkeyReleased):
            return .transcribing

        case (.transcribing, .transcriptFinalized(let text)):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .failed(.noSpeechDetected)
                : .cleaning
        case (.cleaning, .cleanupFinished):
            return .injecting
        case (.injecting, .injectionFinished):
            return .idle

        default:
            return nil
        }
    }

    /// True while the microphone is, or may be, capturing.
    ///
    /// Drives the HUD and — more importantly — the watchdog. If this is true for longer than any
    /// plausible utterance, the mic is stuck open and we tear down regardless of what the OS told us.
    public var isCapturing: Bool {
        state == .arming || state == .recording
    }

    /// True once the utterance is over, either way.
    public var isTerminal: Bool {
        if case .failed = state { return true }
        return state == .idle
    }
}
