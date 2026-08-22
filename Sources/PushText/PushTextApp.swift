import SwiftUI
import PushTextCore
import PushTextKit

/// Composition root. Every dependency is constructed here and injected downward, so nothing
/// deeper in the app reaches for a singleton or a framework on its own.
@main
struct PushTextApp: App {
    @State private var model: AppModel
    /// Held for the process lifetime: releasing the monitor tears down the event tap.
    private let hotkey: CGEventTapHotkeyMonitor

    init() {
        // Headless proof of the event tap, before any UI exists. Never returns when requested.
        if HotkeyProbe.isRequested {
            HotkeyProbe.runAndExit()
        }
        if AudioProbe.isRequested {
            AudioProbe.runAndExit()
        }
        if InjectionProbe.isRequested {
            InjectionProbe.runAndExit()
        }
        // Gated on the SDK, not the OS: TranscriptionProbe drives SpeechAnalyzer, whose symbols do
        // not exist when building against an older SDK (CI's macos-15 runner).
        #if canImport(FoundationModels)
        if TranscriptionProbe.isRequested {
            TranscriptionProbe.runAndExit()
        }
        #endif
        // No probe took over, so any probe-tuning variable still set is a misconfiguration that
        // would otherwise launch the UI and look like a hung probe.
        ProbeActivation.enforceOrExit()

        // Phase 1 wiring (#12, #39): Apple's on-device SpeechAnalyzer, now that Xcode 26 ships the
        // SDK and #11 confirmed the streaming path works on this OS build. Systems that cannot run
        // it get an engine that REFUSES rather than the mock, whose canned phrases would otherwise
        // be typed into a real document — see TranscriptionEngineFactory.
        let model = AppModel(engine: TranscriptionEngineFactory.makeDefault(),
                             capture: AVAudioEngineCapture(),
                             injector: PasteboardTextInjector())
        self.model = model

        // The tap is the only thing that can fail at launch, and it fails for one reason worth
        // telling the user about: Accessibility is not granted. Surfaced in the menu rather than
        // thrown, because a menu-bar app that crashes on launch gives them nothing to act on.
        let monitor = CGEventTapHotkeyMonitor()
        self.hotkey = monitor
        do {
            try monitor.start { edge in
                Task { @MainActor in model.handle(edge) }
            }
        } catch {
            model.reportStartupFailure(
                "Hold-to-dictate needs Accessibility. Grant it in System Settings > Privacy & "
                + "Security > Accessibility, then relaunch PushText.")
        }
    }

    var body: some Scene {
        MenuBarExtra("PushText", systemImage: model.menuBarSymbol) {
            MenuContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Observable app state. Thin on purpose: the transition rules live in `DictationMachine`, in
/// Core, where they are testable without a running app.
@MainActor
@Observable
final class AppModel {
    private(set) var machine = DictationMachine()
    private(set) var lastTranscript: String?
    /// Non-nil when something at launch left the app unable to dictate. Shown in the menu.
    private(set) var startupFailure: String?
    private let engine: any TranscriptionEngine
    private let capture: (any AudioCapture)?
    private let injector: (any TextInjector)?
    private let feed: AudioFeed
    private var captureWatchdog: Timer?
    /// Text waiting to be injected, held between `transcriptFinalized` and `injectionFinished`.
    private var pendingText: String?

    /// Longest a single utterance may hold the microphone before it is force-closed.
    ///
    /// This is the ONLY defence against the measured stuck-capture case. A stalled `.defaultTap` can
    /// drop a modifier key-up so thoroughly that macOS's own `flagsState` stays latched — the event
    /// stream and the live flag state are then both wrong, and every state-based recovery is blind.
    /// Elapsed time is the one signal that cannot be corrupted that way.
    ///
    /// Generous on purpose: it exists to stop a stuck microphone, not to cut off a long sentence.
    var maximumCaptureDuration: TimeInterval = 120

    /// `capture` and `injector` are optional so the state-machine tests can construct a model with
    /// no OS dependencies at all. A model without them still transitions correctly; it simply has
    /// no audio to record and nowhere to put text.
    init(engine: any TranscriptionEngine,
         capture: (any AudioCapture)? = nil,
         injector: (any TextInjector)? = nil,
         machine: DictationMachine = DictationMachine()) {
        self.engine = engine
        self.capture = capture
        self.injector = injector
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

        guard machine.state != previous else { return }
        performEffects(entering: machine.state, on: event)
    }

    /// Drives the side effects from the STATE, never from the raw key edge.
    ///
    /// The machine already decides what a press means in each state - duplicate key-downs from an
    /// event tap are normal, and reacting to the edge directly would start a second utterance on
    /// one of them. Reacting to a state CHANGE makes that impossible by construction.
    private func performEffects(entering state: DictationState, on event: DictationEvent) {
        switch state {
        case .arming:
            Task { await self.openUtterance() }

        case .transcribing:
            Task { await self.closeUtterance() }

        case .cleaning:
            // No CleanupProvider yet (#14). The machine requires this transition, so pass the
            // transcript through unchanged rather than inventing a stage.
            if case .transcriptFinalized(let text) = event {
                pendingText = text
                lastTranscript = text
                apply(.cleanupFinished(text))
            }

        case .injecting:
            let text = pendingText ?? ""
            Task { await self.injectText(text) }

        case .failed:
            Task { await self.teardown() }

        default:
            break
        }
    }

    private func openUtterance() async {
        do {
            try await feed.begin()
            // Capture starts AFTER the engine is ready, so no buffer can arrive with nowhere to go.
            try capture?.start { [feed] buffer in feed.submit(buffer) }
            apply(.audioStarted)
        } catch {
            await feed.cancel()
            capture?.stop()
            apply(.failure(Self.classify(error)))
        }
    }

    private func closeUtterance() async {
        // Stop the microphone FIRST: everything already submitted is still in the feed's queue, and
        // leaving it open would keep appending audio the user did not intend to dictate.
        capture?.stop()
        do {
            let transcript = try await feed.finish()
            apply(.transcriptFinalized(transcript.text))
        } catch {
            apply(.failure(.transcriptionFailed))
        }
    }

    private func injectText(_ text: String) async {
        guard let injector else {
            apply(.injectionFinished)
            return
        }
        do {
            try await injector.inject(text)
            pendingText = nil
            apply(.injectionFinished)
        } catch {
            apply(.failure(.injectionFailed))
        }
    }

    /// Runs on every failure path. The microphone staying open is the worst outcome this app has -
    /// worse than losing the utterance - so it is closed unconditionally.
    private func teardown() async {
        capture?.stop()
        await feed.cancel()
        pendingText = nil
    }

    private static func classify(_ error: Error) -> DictationFailure {
        if let captureError = error as? AVAudioEngineCapture.CaptureError,
           captureError == .microphoneNotAuthorized {
            return .permissionDenied
        }
        return .transcriptionFailed
    }

    private func startCaptureWatchdog() {
        stopCaptureWatchdog()
        guard maximumCaptureDuration > 0 else { return }
        let timer = Timer(timeInterval: maximumCaptureDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.apply(.watchdogExpired) }
        }
        captureWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCaptureWatchdog() {
        captureWatchdog?.invalidate()
        captureWatchdog = nil
    }

    /// Whether a capture-duration watchdog is currently armed.
    var isCaptureWatchdogArmed: Bool { captureWatchdog != nil }

    /// Maps a raw key edge to the dictation event it implies.
    func handle(_ edge: HotkeyEdge) {
        apply(edge == .pressed ? .hotkeyPressed : .hotkeyReleased)
    }

    var statusText: String {
        switch machine.state {
        case .idle: "Ready"
        case .arming: "Starting..."
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .cleaning: "Polishing"
        case .injecting: "Inserting"
        case .failed(let reason): Self.describe(reason)
        }
    }

    private static func describe(_ failure: DictationFailure) -> String {
        switch failure {
        case .permissionDenied: "Permission needed"
        case .noSpeechDetected: "Didn't catch that"
        case .transcriptionFailed: "Transcription failed"
        case .injectionFailed: "Couldn't insert text"
        case .cancelled: "Cancelled"
        }
    }
}

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PushText")
                .font(.headline)
            Text(model.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Phase 0 scaffold. The hotkey monitor, HUD panel, history list, permission cards and
            // Sparkle update control land in 0.3–0.10; this is here to prove the shell launches
            // and the menu renders.
            if let failure = model.startupFailure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Hold Right Option to dictate")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let transcript = model.lastTranscript, !transcript.isEmpty {
                Text(transcript)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit PushText") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 240)
    }
}
