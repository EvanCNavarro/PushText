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
        // Phase 0 wiring: the mock engine stands in for Apple's SpeechAnalyzer, which cannot be
        // compiled until Xcode 26 is installed. Swapped at Phase 2 — see PLAN.md §4.
        model = AppModel(engine: MockTranscriptionEngine())
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

    init(engine: any TranscriptionEngine) {
        self.engine = engine
    }

    var menuBarSymbol: String {
        machine.isCapturing ? "waveform.circle.fill" : "waveform"
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
