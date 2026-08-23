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
    /// Hotkey down. Audio engine and transcriber starting. Not yet capturing speech.
    ///
    /// This phase exists to buy latency: work started on key-down gets the user's entire speech
    /// duration for free, which is the largest win available and the main reason cleanup runs
    /// in-process rather than over HTTP (PLAN.md sec 2.1).
    ///
    /// It used to say the language model was PREWARMED here, and nothing did that - the only
    /// model work on this path was an asset download that blocked the first utterance (#36).
    /// Installation now happens at launch via `TranscriptionEngine.prepare()`, and this phase
    /// starts the analyzer for an already-installed model.
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
    /// The on-device model has not finished installing yet (#36).
    ///
    /// Distinct from `transcriptionFailed` because the user's next move differs: this one resolves
    /// itself if they wait, and telling them "Transcription failed" would send them looking for a
    /// fault that does not exist.
    case modelNotReady
    /// The user let go before saying anything, or cancelled.
    case cancelled
}

/// Things that happen to a dictation, from outside.
public enum DictationEvent: Equatable, Sendable {
    case hotkeyPressed
    case hotkeyReleased
    /// A release whose press was short enough to be a TAP rather than a dictation.
    ///
    /// Distinct from `hotkeyReleased` because the two mean opposite things: a hold's release ENDS an
    /// utterance, and a tap's release means there was never an utterance to end. The machine already
    /// said so - `(.arming, .hotkeyReleased) -> .idle`, "too short to be speech" - but that rule
    /// raced capture start and lost by 4 ms on the real event tap (#105), so the tap became a 74 ms
    /// utterance and the double press that followed arrived in a state that could not accept it.
    case hotkeyTapReleased
    /// Two presses in quick succession: start a LATCHED utterance that outlives the key release.
    case hotkeyDoublePressed
    /// Stop and transcribe. What releasing the key does in hold mode, as an explicit request the
    /// HUD's confirm control can also send.
    case endRequested
    /// Stop and DISCARD. Deliberately distinct from `endRequested`: nothing is transcribed and
    /// nothing is injected. Without it, an utterance the user regrets is typed into their document
    /// regardless.
    case cancelRequested
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

/// How the current utterance was started, which decides what the key release means.
public enum DictationInputMode: Equatable, Sendable {
    /// Recording lasts as long as the key is held. The fast path for a short phrase.
    case hold
    /// Recording continues after the key is released, until ended or cancelled. Exists because
    /// holding a modifier through a long dictation is uncomfortable and makes the key unusable for
    /// anything else while held.
    case latched
}

/// The legal transitions. Anything not listed here is ignored, and ignoring is deliberate:
/// duplicate key-down events from an event tap are normal, not exceptional.
public struct DictationMachine: Sendable {
    public private(set) var state: DictationState
    /// How the CURRENT utterance was started. Meaningless outside one, and reset on every start so
    /// a latched utterance cannot leak its mode into the next hold.
    public private(set) var inputMode: DictationInputMode = .hold

    public init(state: DictationState = .idle) {
        self.state = state
    }

    /// Forces latched mode for tests that start from a mid-utterance state.
    mutating func startLatchedForTesting() {
        inputMode = .latched
    }

    /// Applies an event. Returns `true` if the state actually changed.
    @discardableResult
    public mutating func apply(_ event: DictationEvent) -> Bool {
        let next = Self.transition(from: state, on: event, mode: inputMode)
        guard let next, next != state else { return false }

        // Set the mode as the utterance STARTS, not when the event arrives, so a press that merely
        // ends a latched utterance cannot silently re-arm it as a hold.
        if next == .arming {
            inputMode = (event == .hotkeyDoublePressed) ? .latched : .hold
        }
        state = next
        return true
    }

    /// Pure transition function — the whole machine, in one place, testable without a machine.
    public static func transition(
        from state: DictationState,
        on event: DictationEvent,
        mode: DictationInputMode = .hold
    ) -> DictationState? {
        // Split from the main table purely to keep each function within the complexity limit; the
        // rules still read top to bottom in one file.
        if let recovery = recoveryTransition(from: state, on: event) { return recovery }
        switch latchTransition(from: state, on: event, mode: mode) {
        case .to(let next): return next
        case .ignore: return nil
        case .unhandled: return progressTransition(from: state, on: event)
        }
    }

    /// Three outcomes, not two. `ignore` and `unhandled` are different answers and collapsing them
    /// into `nil` is a live defect: a latched utterance's key release must be IGNORED, and returning
    /// nil for it fell through to the mode-independent table, which ended the utterance - exactly
    /// the behaviour latching exists to prevent.
    private enum LatchOutcome {
        case to(DictationState)
        case ignore
        case unhandled
    }

    /// Everything that depends on HOW the utterance was started, plus the explicit end/cancel
    /// requests the HUD sends. Consulted before the mode-independent table so a latched utterance
    /// can suppress the key-release rule rather than inherit it.
    private static func latchTransition(
        from state: DictationState,
        on event: DictationEvent,
        mode: DictationInputMode
    ) -> LatchOutcome {
        switch (state, event) {
        case (.idle, .hotkeyDoublePressed), (.failed, .hotkeyDoublePressed):
            return .to(.arming)

        // A latched utterance ignores the release entirely - both the one following the starting
        // double-press and the one following the ending press.
        case (.arming, .hotkeyReleased), (.recording, .hotkeyReleased),
             (.arming, .hotkeyTapReleased), (.recording, .hotkeyTapReleased):
            return mode == .latched ? .ignore : .unhandled

        // The press that ENDS a latched utterance is itself a tap, so its release arrives here
        // while transcribing. Both spellings must be ignored or that release would end the
        // utterance a second time.
        case (.transcribing, .hotkeyReleased), (.transcribing, .hotkeyTapReleased):
            return .ignore

        // Press again to end, but only when latched: in hold mode a press while recording is a
        // duplicate key-down from the tap, which must stay ignored.
        case (.recording, .hotkeyPressed):
            return mode == .latched ? .to(.transcribing) : .ignore

        case (.arming, .endRequested), (.recording, .endRequested):
            return .to(.transcribing)

        // Cancel reaches idle WITHOUT passing through transcribing: anything that reaches
        // transcribing eventually injects, and the point of cancel is that nothing is typed. It is
        // not routed through `.failed` either - the user did exactly what they meant to.
        case (.arming, .cancelRequested), (.recording, .cancelRequested):
            return .to(.idle)

        default:
            return .unhandled
        }
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

        // The same judgement as the arming case above, applied where it actually bites. Capture
        // starts ~70 ms after arming and a tap releases ~74 ms after the press (#105), so a tap
        // reaches `.recording` and the arming rule never sees it. Deciding from the PRESS DURATION
        // rather than from which state won the race makes the outcome independent of a 4 ms margin.
        case (.arming, .hotkeyTapReleased), (.recording, .hotkeyTapReleased):
            return .idle

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

/// How far along the on-device model's installation is (#76).
///
/// #36 moved the download OFF the dictation path so the first key-down no longer blocks. This is
/// the other half: telling the user it is happening. A cold machine otherwise shows an app that
/// refuses to dictate with no indication of why or for how long.
public enum ModelPreparation: Equatable, Sendable {
    case notStarted
    case preparing(fraction: Double)
    case ready
    /// Installation failed. Distinct from `preparing` because waiting will not fix it.
    case failed(String)
}
