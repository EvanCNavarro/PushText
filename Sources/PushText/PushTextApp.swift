import SwiftUI
import PushTextCore
import PushTextKit

/// Composition root. Every dependency is constructed here and injected downward, so nothing
/// deeper in the app reaches for a singleton or a framework on its own.
@main
struct PushTextApp: App {
    @State private var model: AppModel

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
        // Phase 1 wiring (#12): Apple's on-device SpeechAnalyzer, now that Xcode 26 ships the SDK
        // and #11 confirmed the streaming path works on this OS build. Systems that cannot run it
        // get an engine that REFUSES rather than the mock, whose canned phrases would otherwise be
        // typed into a real document — see TranscriptionEngineFactory.
        model = AppModel(engine: TranscriptionEngineFactory.makeDefault())
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
    private let engine: any TranscriptionEngine
    private var captureWatchdog: Timer?

    /// Longest a single utterance may hold the microphone before it is force-closed.
    ///
    /// This is the ONLY defence against the measured stuck-capture case. A stalled `.defaultTap` can
    /// drop a modifier key-up so thoroughly that macOS's own `flagsState` stays latched — the event
    /// stream and the live flag state are then both wrong, and every state-based recovery is blind.
    /// Elapsed time is the one signal that cannot be corrupted that way.
    ///
    /// Generous on purpose: it exists to stop a stuck microphone, not to cut off a long sentence.
    var maximumCaptureDuration: TimeInterval = 120

    init(engine: any TranscriptionEngine, machine: DictationMachine = DictationMachine()) {
        self.engine = engine
        self.machine = machine
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
        machine.apply(event)
        guard machine.isCapturing != wasCapturing else { return }
        if machine.isCapturing {
            startCaptureWatchdog()
        } else {
            stopCaptureWatchdog()
        }
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
            Text("Hold Right Option to dictate")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
