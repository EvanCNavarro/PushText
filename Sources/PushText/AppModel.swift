import SwiftUI
import AVFoundation
import OSLog
import PushTextCore
import PushTextKit

/// Observable app state. Thin on purpose: the transition rules live in `DictationMachine`, in
/// Core, where they are testable without a running app.
@MainActor
@Observable
final class AppModel {
    private(set) var machine = DictationMachine()
    private(set) var lastTranscript: String?
    /// Non-nil when something at launch left the app unable to dictate. Shown in the menu.
    private(set) var startupFailure: String?

    /// Serialises `openUtterance`, so two of them can never be inside `feed.begin()` at once.
    ///
    /// Ordering alone is not enough (the epoch below handles identity), but without it the two
    /// `begin` calls can land in either order, and the LATER one owns the feed - so the task that
    /// abandons could still be the one holding the live utterance.
    private var openTask: Task<Void, Never>?

    /// Which `.arming` a task belongs to.
    ///
    /// `machine.state == .arming` cannot distinguish "still MY arming" from "a NEW arming that
    /// replaced mine" - and in the #55 trace it is exactly a new one, so the stale task sailed
    /// past the guard and adopted the successor's utterance.
    private var armingEpoch = 0

    /// The utterance this model currently owns, or nil between utterances (#55).
    ///
    /// Two `openUtterance()` tasks can be in flight at once - a quick tap goes `arming -> idle`
    /// while its task still awaits `feed.begin()`, and a double press immediately arms the next.
    /// Each task therefore has to say WHICH utterance it is finishing or abandoning; without that
    /// the abandoning one tore down its successor.
    private var utterance: AudioFeed.Utterance?

private let engine: any TranscriptionEngine
    private let capture: (any AudioCapture)?
    private let injector: (any TextInjector)?
    private let feed: AudioFeed
    /// The HUD, owned by its own type - see HUDDriver.
    private let hud: HUDDriver

    /// The level the HUD waveform is currently drawing. Exposed for tests: planting a broken
    /// sample feed left every suite green, which meant nothing asserted that captured audio ever
    /// reaches the meter - a break there shows up only as a HUD that sits flat while recording.
    var currentAudioLevel: Double { hud.levels.current }
    /// Turns raw edges into events, so a double press can start a latched utterance (#46).
    private var pressPattern = PressPatternRecognizer()
    private let watchdog = CaptureWatchdog()
    /// Text waiting to be injected, held between `transcriptFinalized` and `injectionFinished`.
    private var pendingText: String?

    private let advisor = PermissionAdvisor()   // see PermissionAdvisor

    var permissionAdvice: [(permission: Permission, advice: PermissionAdvice)] { advisor.advice }

    var permissionProbe: (any PermissionProbe)? {
        get { advisor.probe }
        set { advisor.probe = newValue }
    }

    func refreshPermissionAdvice() { advisor.refresh() }

    /// Model installation, owned by its own type - see ModelPreparer.
    private let preparer = ModelPreparer()

    var modelPreparation: ModelPreparation { preparer.state }

    func prepareModel() async { await preparer.prepare(engine: engine) }

    /// What the menu says about preparation, or nil when there is nothing to say.
    var modelPreparationMessage: String? { Self.preparationMessage(for: modelPreparation) }

    /// Where completed dictations are kept (#10). Optional so the state-machine tests can run with
    /// no filesystem at all.
    /// The user's rewrite rules (#82). Loaded per utterance, never cached - the file is hand-edited.
    /// Cleanup, the user's dictionary and the history record, in the one order that is correct -
    /// see TranscriptFinisher.
    private let finisher: TranscriptFinisher
    /// Held between `.transcribing` and `.cleaning` because the history record needs the DURATION,
    /// and the machine's event carries only text.
    private var pendingTranscript: Transcript?

    /// What the last utterance lost, phrased for a human, or nil when it lost nothing (#71).
    private(set) var lastCaptureWarning: String?

    /// When the user stopped speaking, for the release-to-text figure the app logs (#15).
    ///
    /// The first such number this project had was subtracted by hand from two os_log timestamps,
    /// which is not a measurement anyone can re-read later. Emitting the elapsed value makes every
    /// real dictation a data point. `ContinuousClock` because it does not jump when the wall clock
    /// is adjusted mid-utterance.
    private var releasedAt: ContinuousClock.Instant?

    /// Longest a single utterance may hold the microphone before it is force-closed.
    /// Forwarded to `CaptureWatchdog`, which owns the timer and the reasoning.
    var maximumCaptureDuration: TimeInterval {
        get { watchdog.maximumDuration }
        set { watchdog.maximumDuration = newValue }
    }

    /// `capture` and `injector` are optional so the state-machine tests can construct a model with
    /// no OS dependencies at all. A model without them still transitions correctly; it simply has
    /// no audio to record and nowhere to put text.
    init(engine: any TranscriptionEngine,
         capture: (any AudioCapture)? = nil,
         injector: (any TextInjector)? = nil,
         indicator: (any DictationIndicator)? = nil,
         history: (any HistoryStore)? = nil,
         dictionary: (any DictionaryStore)? = nil,
         cleanup: (any CleanupProvider)? = nil,
         machine: DictationMachine = DictationMachine()) {
        self.engine = engine
        self.capture = capture
        self.injector = injector
        self.hud = HUDDriver(indicator: indicator)
        self.finisher = TranscriptFinisher(cleanup: cleanup, dictionary: dictionary,
                                           history: history)
        self.feed = AudioFeed(engine: engine)
        self.machine = machine
    }

    func reportStartupFailure(_ message: String) {
        startupFailure = message
    }

    var menuBarSymbol: String {
        machine.isCapturing ? "waveform.circle.fill" : "waveform"
    }

    /// Feeds one event into the dictation machine.
    ///
    /// The composition root routes hotkey edges here; keeping the mapping in one place means the
    /// shell never decides what a key press MEANS, it only reports that one happened.
    func apply(_ event: DictationEvent) {
        let wasCapturing = machine.isCapturing
        let previous = machine.state
        machine.apply(event)

        if machine.isCapturing != wasCapturing {
            if machine.isCapturing {
                startCaptureWatchdog()
            } else {
                stopCaptureWatchdog()
            }
        }

        guard machine.state != previous else {
            dictationLog.debug("""
                event=\(String(describing: event), privacy: .public) \
                ignored in state=\(String(describing: previous), privacy: .public)
                """)
            return
        }
        dictationLog.info("""
            state \(String(describing: previous), privacy: .public) -> \
            \(String(describing: self.machine.state), privacy: .public)
            """)
        performEffects(entering: machine.state, from: previous, on: event)
    }

    /// Drives the side effects from the STATE, never from the raw key edge.
    ///
    /// The machine already decides what a press means in each state - duplicate key-downs from an
    /// event tap are normal, and reacting to the edge directly would start a second utterance on
    /// one of them. Reacting to a state CHANGE makes that impossible by construction.
    private func performEffects(
        entering state: DictationState,
        from previous: DictationState,
        on event: DictationEvent
    ) {
        // Reaching idle from an ACTIVE utterance means the user cancelled; reaching it from
        // `.injecting` is an utterance that completed normally and needs no teardown.
        let previousWasActive = previous == .arming || previous == .recording
        updateIndicator(for: state)

        switch state {
        case .arming:
            // Key-down. Warming here overlaps the model's start-up with the user's speech, which
            // is the entire latency argument: 4-8 s of talking against a warm-up that wants ~1 s.
            Task { await self.finisher.prewarm() }
            armingEpoch += 1
            let epoch = armingEpoch
            let previous = openTask
            openTask = Task {
                // Let the outgoing attempt finish abandoning before this one opens anything.
                await previous?.value
                await self.openUtterance(epoch: epoch)
            }

        case .transcribing:
            Task { await self.closeUtterance() }

        case .cleaning:
            if case .transcriptFinalized = event {
                Task { await self.finishText() }
            }

        case .injecting:
            let text = pendingText ?? ""
            Task { await self.injectText(text) }

        case .failed:
            closeMicrophone()
            Task { await self.teardown() }

        case .idle where previousWasActive:
            // Reached idle from an active utterance: that is a CANCEL. Tear down without asking the
            // engine for a transcript, because the point of cancel is that nothing is typed.
            //
            // Logged because a cancel otherwise appears in the log as `recording -> idle` and
            // nothing else, which is indistinguishable from the utterance having failed silently -
            // and "the microphone closed" was a claim no log line could support (#107).
            dictationLog.info("cancelled: capture closed, nothing injected")
            closeMicrophone()
            Task { await self.teardown() }

        default:
            break
        }
    }

    private func updateIndicator(for state: DictationState) {
        hud.update(for: state,
                   isCapturing: { [weak self] in self?.machine.isCapturing ?? false },
                   onCancel: { [weak self] in self?.apply(.cancelRequested) },
                   onConfirm: { [weak self] in self?.apply(.endRequested) })
    }

    private func openUtterance(epoch: Int) async {
        // Cheap pre-check: the utterance may already be over before this task got scheduled.
        guard epoch == armingEpoch, machine.state == .arming else {
            dictationLog.info("openUtterance skipped: superseded before it began")
            return
        }
        do {
            let token = try await feed.begin()

            // The utterance may have ENDED while the engine was starting - a quick tap goes
            // arming -> idle, and a cancel can arrive at any moment. Opening the microphone now
            // would leave it running for an utterance that no longer exists, and would let a
            // stale start clobber the next one.
            guard epoch == armingEpoch, machine.state == .arming else {
                dictationLog.info("openUtterance abandoned: state moved on while starting")
                // `token`, not "whatever is installed": a newer utterance may already own the feed,
                // and cancelling THAT is exactly the bug this argument exists to prevent (#55).
                await feed.cancel(token)
                return
            }
            utterance = token

            // Capture starts AFTER the engine is ready, so no buffer can arrive with nowhere to go.
            hud.levels.reset()
            // `levels` captured directly, not through `hud`: it is nonisolated precisely so this
            // drain-queue callback needs no main-actor hop per buffer.
            let levels = hud.levels
            try capture?.start { [feed, levels] buffer in
                feed.submit(buffer)
                levels.record(buffer.samples)
            }
            dictationLog.info("capture started")
            apply(.audioStarted)
        } catch {
            dictationLog.error("openUtterance FAILED: \(String(describing: error), privacy: .public)")
            if let token = utterance { await feed.cancel(token); utterance = nil }
            capture?.stop()
            apply(.failure(Self.classify(error)))
        }
    }

    private func closeUtterance() async {
        releasedAt = ContinuousClock.now
        // Stop the microphone FIRST: everything already submitted is still in the feed's queue, and
        // leaving it open would keep appending audio the user did not intend to dictate.
        capture?.stop()
        guard let token = utterance else {
            // No utterance to finish. Failing loudly beats hanging in `.transcribing`, which is
            // precisely what #55 did.
            dictationLog.error("closeUtterance with no open utterance")
            apply(.failure(.transcriptionFailed))
            return
        }
        utterance = nil
        // Read BEFORE the transcript: the counters describe the capture that just stopped, and the
        // next utterance resets them.
        lastCaptureWarning = capture.map { Self.captureWarning(for: $0.health) } ?? nil
        if let lastCaptureWarning {
            dictationLog.error("capture lost audio: \(lastCaptureWarning, privacy: .public)")
        }
        do {
            let transcript = try await feed.finish(token)
            dictationLog.info("transcript chars=\(transcript.text.count) duration=\(transcript.duration)")
            // RAW. Cleanup, the user's dictionary and the history record all happen in `.cleaning`,
            // in that order - see `finishText`.
            pendingTranscript = transcript
            apply(.transcriptFinalized(transcript.text))
        } catch {
            dictationLog.error("finishUtterance FAILED: \(String(describing: error), privacy: .public)")
            apply(.failure(.transcriptionFailed))
        }
    }

    private func finishText() async {
        let transcript = pendingTranscript ?? Transcript(text: "", duration: 0)
        pendingTranscript = nil
        let text = await finisher.finish(transcript)
        pendingText = text
        lastTranscript = text
        apply(.cleanupFinished(text))
    }

    private func injectText(_ text: String) async {
        guard let injector else {
            apply(.injectionFinished)
            return
        }
        do {
            try await injector.inject(text)
            // This spans mic teardown, finalize, injection AND the injector's post-paste settle
            // wait, so it is strictly larger than the engine's own finalize time - the probe
            // measures that part alone (docs/verification/task15-latency.md).
            if let releasedAt {
                let elapsed = ContinuousClock.now - releasedAt
                let millis = Double(elapsed.components.seconds) * 1000
                    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                // `privacy: .public` or os_log redacts this to <private> - which is exactly what
                // the first real dictation after #15 shipped logged. This line exists to be read.
                let ms = String(format: "%.0f", millis)
                dictationLog.info("injected chars=\(text.count) releaseToText=\(ms, privacy: .public)ms")
            } else {
                dictationLog.info("injected chars=\(text.count)")
            }
            releasedAt = nil
            pendingText = nil
            apply(.injectionFinished)
        } catch {
            dictationLog.error("inject FAILED: \(String(describing: error), privacy: .public)")
            apply(.failure(.injectionFailed))
        }
    }

    /// Runs on every failure path. The microphone staying open is the worst outcome this app has -
    /// worse than losing the utterance - so it is closed unconditionally.
    /// Synchronous on purpose. A microphone left open is the worst outcome this app has - worse
    /// than losing the utterance - so it closes in the same turn as the decision to stop, not
    /// whenever a Task happens to be scheduled. Idempotent, so the async teardown may call it again.
    private func closeMicrophone() {
        capture?.stop()
    }

    private func teardown() async {
        closeMicrophone()
        if let token = utterance {
            utterance = nil
            await feed.cancel(token)
        }
        pendingText = nil
    }

    private func startCaptureWatchdog() {
        watchdog.arm { [weak self] in self?.apply(.watchdogExpired) }
    }

    private func stopCaptureWatchdog() { watchdog.disarm() }

    /// Whether a capture-duration watchdog is currently armed.
    var isCaptureWatchdogArmed: Bool { watchdog.isArmed }

    /// Maps a raw key edge to the dictation event it implies, including the double press that
    /// starts a latched utterance.
    ///
    /// The timestamp is a parameter with a monotonic default so tests can drive the double-press
    /// windows deterministically instead of racing a wall clock. `systemUptime` rather than
    /// `Date()`: it cannot step backwards when the clock is adjusted.
    func handle(_ edge: HotkeyEdge, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        apply(pressPattern.handle(edge, at: time))
    }
}
