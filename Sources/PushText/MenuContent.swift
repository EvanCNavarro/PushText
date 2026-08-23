import SwiftUI
import AppKit
import MacFaceKit
import PushTextCore
import PushTextKit

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
            if model.startupFailure != nil || !model.permissionAdvice.isEmpty
                || model.modelPreparationMessage != nil {
                SectionCard("NEEDS ATTENTION") {
                    // Model preparation first: while it is downloading, nothing else in this
                    // section can be acted on usefully anyway (#76).
                    if let preparing = model.modelPreparationMessage {
                        Text(preparing)
                            .font(Tokens.caption)
                            .foregroundStyle(Tokens.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let failure = model.startupFailure {
                        Text(failure)
                            .font(Tokens.body)
                            .foregroundStyle(Tokens.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // One row per permission that is not granted. The copy differs by STATE, which
                    // is the entire reason the probe reports three of them (#6).
                    // A rule between rows, matching AppIdentityCard's use of Divider. Rendered
                    // without one, three stacked rows read as a single block of prose: SectionCard
                    // puts 10pt between children and a row puts 4pt inside itself, and that ratio
                    // is not enough separation to group each title with its own button.
                    ForEach(Array(model.permissionAdvice.enumerated()), id: \.element.permission) { index, entry in
                        if index > 0 || model.startupFailure != nil { Divider() }
                        PermissionRow(advice: entry.advice) { actions.resolvePermission(entry.advice) }
                    }
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
                LastTranscriptCard(transcript: transcript, warning: model.lastCaptureWarning)
            }
        }
        .frame(width: 320)
        .background(Tokens.panel)
        // Recomputed on OPEN, not cached at launch. The user changes these in System Settings while
        // this menu is closed, so a launch-time value is stale exactly when they come back to check.
        .onAppear { model.refreshPermissionAdvice() }
    }
}

/// One unmet permission: what is missing, why it matters, and a way out.
///
/// Always actionable. A row that names a problem and offers nothing is worse than no row, because
/// the user now knows they are stuck and still cannot move.
struct PermissionRow: View {
    let advice: PermissionAdvice
    /// A closure, not the whole `AppActions`: a row needs one verb, and depending on the object
    /// that owns Sparkle's updater makes the row unrenderable outside a running app.
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.micro) {
            Text(advice.title)
                .font(Tokens.body)
                .foregroundStyle(Tokens.warning)
            Text(advice.detail)
                .font(Tokens.caption)
                .foregroundStyle(Tokens.muted)
                .fixedSize(horizontal: false, vertical: true)
            ActionRow(title: advice.actionLabel,
                      systemImage: advice.canPromptInApp ? "checkmark.shield" : "gearshape",
                      action: onResolve)
        }
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

/// The last transcript, with a control that copies it and says so (#106).
///
/// Its own view because it owns STATE - the confirmation has to revert on its own - and `MenuContent`
/// is otherwise stateless. Putting an `@State` there would make the whole menu a stateful view for
/// the sake of one icon.
private struct LastTranscriptCard: View {
    let transcript: String
    let warning: String?

    @State private var copied = false

    var body: some View {
        SectionCard("LAST TRANSCRIPT") {
            // Beside the transcript, not in NEEDS ATTENTION: this describes THIS utterance and stops
            // being true at the next one, whereas that section is for conditions that persist until
            // the user fixes them (#71).
            if let warning {
                Text(warning)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Top-aligned: the transcript wraps to four lines and the control belongs beside its
            // FIRST line, not floating against the vertical centre of a paragraph.
            HStack(alignment: .top, spacing: Tokens.space) {
                Text(transcript)
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.text)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                copyControl
            }
        }
    }

    /// `IconButton`, the same control the `...` overflow uses - `controlButton` size, `row` fill,
    /// `line` border, and the hover treatment already defined by `IconButtonStyle`. Not
    /// `GhostIconButton`: that is the borderless variant, and using it here made the copy control a
    /// different size and hover behaviour from the only other icon control in the menu.
    ///
    /// `IconButton`'s own docstring names this exact trap - it owns its hover state "so callers
    /// never re-wire it (the bug where the `...` was styled by hand)".
    private var copyControl: some View {
        IconButton(systemImage: copied ? "checkmark" : "doc.on.doc",
                   size: 11,
                   active: copied,
                   accessibilityHint: copied ? "Copied" : "Copy this transcript",
                   action: copy)
            .help(copied ? "Copied" : "Copy this transcript")
            .accessibilityLabel(Text(copied ? "Copied" : "Copy this transcript"))
    }

    /// PLAIN text, not the concealed form injection uses: pressing copy IS the user asking for this
    /// in their clipboard history, and `stage`'s markers tell clipboard managers to discard it.
    private func copy() {
        PasteboardTextInjector.copy(transcript, on: .general)
        copied = true
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            copied = false
        }
    }
}
