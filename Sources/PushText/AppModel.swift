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
    var utterance: AudioFeed.Utterance?

private let engine: any TranscriptionEngine
    let capture: (any AudioCapture)?
    let injector: (any TextInjector)?
    let feed: AudioFeed
    /// The HUD, owned by its own type - see HUDDriver.
    let hud: HUDDriver

    /// The level the HUD waveform is currently drawing. Exposed for tests: planting a broken
    /// sample feed left every suite green, which meant nothing asserted that captured audio ever
    /// reaches the meter - a break there shows up only as a HUD that sits flat while recording.
    var currentAudioLevel: Double { hud.levels.current }
    /// Turns raw edges into events, so a double press can start a latched utterance (#46).
    private var pressPattern = PressPatternRecognizer()
    let watchdog = CaptureWatchdog()
    /// Text waiting to be injected, held between `transcriptFinalized` and `injectionFinished`.
    var pendingText: String?

    // Internal, not private: `AppModel+Permissions` needs it and lives in another file.
    let advisor = PermissionAdvisor()   // see PermissionAdvisor
    /// Set by the composition root, which owns the tap and the capture device (#152). Stored, so it
    /// must live on the type - an extension cannot hold a stored property.
    var onRetryPermission: ((Permission) -> Bool)?

    var permissionAdvice: [(permission: Permission, advice: PermissionAdvice)] { advisor.advice }

    var permissionProbe: (any PermissionProbe)? {
        get { advisor.probe }
        set { advisor.probe = newValue }
    }

    /// Records that a subsystem actually failed for want of a grant (#136).
    ///
    /// Replaces a dead-end sentence. The tap failing used to set `startupFailure` to prose naming a
    /// Settings path - unactionable text sitting directly above rows that have buttons. Routing it
    /// through the advisor gives it the same fix-it row as every other missing grant, and the
    /// failure is stronger evidence than the probe: after a re-sign, `AXIsProcessTrusted()` can
    /// report granted while nothing works.
    func reportPermissionFailure(_ permission: Permission) {
        advisor.runtimeFailures.insert(permission)
        advisor.refresh()
    }

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

    /// The user's settings, owned by their own type - see UserPreferences.
    let preferences: UserPreferences

    /// Held between `.transcribing` and `.cleaning` because the history record needs the DURATION,
    /// and the machine's event carries only text.
    private var pendingTranscript: Transcript?

    /// What the last utterance lost, phrased for a human, or nil when it lost nothing (#71).
    private(set) var lastCaptureWarning: String?

    /// Whether the watchdog, rather than the user, ended the capture that just finished (#197).
    ///
    /// It exists so the transcript can SAY it was cut short. Bobby described the old behaviour as
    /// the app having "just died out" - and with the words now kept, silence about WHY they stop
    /// mid-sentence would still leave him guessing whether it crashed.
    var endedByWatchdog = false

    /// When the user stopped speaking, for the release-to-text figure the app logs (#15).
    ///
    /// The first such number this project had was subtracted by hand from two os_log timestamps,
    /// which is not a measurement anyone can re-read later. Emitting the elapsed value makes every
    /// real dictation a data point. `ContinuousClock` because it does not jump when the wall clock
    /// is adjusted mid-utterance.
    var releasedAt: ContinuousClock.Instant?

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
         sounds: (any DictationSoundPlaying)? = nil,
         muter: DictationMuter? = nil,
         dictionary: (any DictionaryStore)? = nil,
         cleanup: (any CleanupProvider)? = nil,
         settingsStore: (any SettingsStore)? = nil,
         machine: DictationMachine = DictationMachine()) {
        self.engine = engine
        self.capture = capture
        self.injector = injector
        self.hud = HUDDriver(indicator: indicator)
        self.sounds = sounds
        self.muter = muter
        self.finisher = TranscriptFinisher(cleanup: cleanup, dictionary: dictionary,
                                           history: history)
        self.preferences = UserPreferences(store: settingsStore)
        self.feed = AudioFeed(engine: engine)
        self.machine = machine
    }

    /// Plays the start/stop cues (#172). Optional, like every other system capability, so the
    /// state-machine tests construct a model that makes no noise.
    let sounds: (any DictationSoundPlaying)?

    /// Silences the Mac while dictating (#188). Optional for the same reason.
    let muter: DictationMuter?

    func reportStartupFailure(_ message: String) {
        startupFailure = message
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
            // A press the user MEANT, refused because the pipeline is still working (#99).
            // The HUD already shows a busy state, so "something is happening" is visible;
            // that the key just pressed did NOTHING is not, and the speech about to follow
            // it will be lost.
            //
            // Logged at INFO, not debug: the debug line below is invisible to
            // `log stream --info`, which is what every investigation here actually runs, so
            // a swallowed press has read as "no press arrived" more than once.
            if previous.isProcessing, event == .hotkeyPressed || event == .hotkeyDoublePressed {
                let refusedIn = String(describing: previous)
                dictationLog.info("hotkey REFUSED in state=\(refusedIn, privacy: .public)")
                hud.acknowledgeRefusal()
            }
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
        // Reaching idle from any of these is a CANCEL. `.injecting` is absent because idle
        // after injecting is the normal ending, not an abandonment (#109).
        let previousWasActive = previous == .arming || previous == .recording
            || previous == .transcribing || previous == .cleaning
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

        case .recording:
            playCue(.start)          // see AppModel+Cues for why here and not `.arming`
            silenceOutputIfWanted()
            endedByWatchdog = false

        case .transcribing:
            playCue(.stop)
            // The user has stopped speaking, so give the sound back NOW rather than after the
            // transcript lands - cleanup can take seconds and a silent Mac through all of it feels
            // like a bug (#188).
            restoreOutput()
            Task { await self.closeUtterance() }

        case .cleaning:
            if case .transcriptFinalized = event {
                Task { await self.finishText() }
            }

        case .injecting:
            let text = pendingText ?? ""
            Task { await self.injectText(text) }

        case .failed:
            restoreOutput()
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
            restoreOutput()
            closeMicrophone()
            Task { await self.teardown() }

        default:
            break
        }
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
        if endedByWatchdog { lastCaptureWarning = watchdogTruncationWarning }
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
        // `shouldCommit` is checked INSIDE the finisher, before the dictionary and history,
        // because cleanup can take seconds and the user can cancel during it. History is the
        // durable record: a cancelled utterance that still appeared there would break the
        // invariant #97 established, that history equals what was injected.
        guard let text = await finisher.finish(transcript,
                                               cleanupEnabled: preferences.cleanupEnabled,
                                               shouldCommit: { [weak self] in
                                                   self?.machine.state == .cleaning
                                               })
        else { return }
        pendingText = text
        lastTranscript = text
        apply(.cleanupFinished(text))
    }

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
