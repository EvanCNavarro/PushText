import SwiftUI
import AppKit
import PushTextCore

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
