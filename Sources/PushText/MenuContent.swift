import SwiftUI
import AppKit
import MacFaceKit
import PushTextCore

/// The menu-bar popover, built from MacFaceKit rather than raw SwiftUI (#47).
///
/// The design system was declared in `Package.swift` and linked into the binary from commit one
/// while `grep -rn MacFaceKit Sources/` returned nothing - so the app paid the dependency's cost and
/// looked like an unstyled prototype. Same components and tokens as TermTile, so the two apps read
/// as one family: `AppIdentityCard` for identity, `SectionCard` for labelled groups, `MenuRow` and
/// `ActionRow` for rows, `Tokens` for every colour and spacing value rather than hardcoded numbers.
struct MenuContent: View {
    let model: AppModel
    let actions: AppActions

    private let repoURL = URL(string: "https://github.com/EvanCNavarro/PushText")!
    private let licenseURL = URL(string: "https://github.com/EvanCNavarro/PushText/blob/master/LICENSE")!

    private var appInfo: AppInfo { .fromBundle() }

    var body: some View {
        // The sections go INSIDE AppIdentityCard's `content:` builder, not beside it. The card draws
        // the Divider between identity and app content, and applies `Tokens.pad` itself - passing
        // them as siblings skipped the divider and padded the panel twice, which is exactly how the
        // spacing drifted from TermTile's.
        AppIdentityCard(
            name: "PushText",
            version: appInfo.displayVersion,
            repoURL: repoURL,
            licenseURL: licenseURL,
            subtitle: "Hold-to-talk dictation that runs entirely on this Mac.",
            actions: actions.menuActions()
        ) {
            if let failure = model.startupFailure {
                SectionCard("NEEDS ATTENTION") {
                    Text(failure)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SectionCard("STATUS") {
                LabeledLine(label: "State", value: model.statusText)
                LabeledLine(label: "Hotkey", value: "Right Option")
            }

            SectionCard("DICTATE") {
                LabeledLine(label: "Hold", value: "Speak, release to insert")
                LabeledLine(label: "Double-press", value: "Hands-free, press again to end")
            }

            if let transcript = model.lastTranscript, !transcript.isEmpty {
                SectionCard("LAST TRANSCRIPT") {
                    Text(transcript)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.text)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(width: 320)
        .background(Tokens.panel)
    }
}

/// A label/value pair on one row, matching the settings lines in TermTile's panel.
private struct LabeledLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.space) {
            Text(label)
                .font(Tokens.body)
                .foregroundStyle(Tokens.muted)
            Spacer(minLength: Tokens.space)
            Text(value)
                .font(Tokens.body)
                .foregroundStyle(Tokens.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
