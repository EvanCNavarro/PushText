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

            // Shown only when it has something to say (#128). Idle is the state you are in
            // whenever you open this menu, so a permanent row read "Ready" and taught nothing -
            // but this is the app's only surface for a DictationFailure, so the row stays for the
            // six messages that ARE worth interrupting for.
            if let activity = model.activityText {
                SectionCard("STATUS") {
                    LabeledLine(label: "State", value: activity)
                }
            }

            SectionCard("DICTATE") {
                LabeledLine(label: "Hold", value: "Speak, release to insert")
                LabeledLine(label: "Double-press", value: "Hands-free, press again to end")
                if model.preferences.hotkeyBinding == .globe,
                   !model.preferences.globeNoticeDismissed,
                   let clash = GlobeKeySetting.currentAction() {
                    // INFORMATIONAL, not a warning, and dismissible (#190).
                    //
                    // It was a NoticeCard with a warning triangle and no way to silence it. Bobby:
                    // "it looks like something is wrong by having this". Nothing IS wrong - his
                    // dictation works - and an orange triangle on a working app is how a person
                    // learns to ignore the warnings that do matter.
                    //
                    // It is also advice about a CHOICE. Somebody may want Globe to do both things,
                    // and an app that keeps telling them about a decision they have made is nagging.
                    GlobeKeyNote(action: clash.describedForUser) {
                        model.preferences.globeNoticeDismissed = true
                    }
                }

                RecorderLine(label: "Hotkey",
                             current: model.preferences.hotkeyBinding,
                             onRecordingChange: { model.preferences.isRecordingHotkey = $0 },
                             onCapture: { model.preferences.hotkeyBinding = $0 })
            }

            SectionCard("GENERAL") {
                // Read from SMAppService every time, never from a stored copy (#162). The user can
                // turn this off in System Settings > General > Login Items without telling us, and a
                // cached Bool would keep drawing ON while the app never started - the same shape as
                // the permission rows that claimed a grant the app did not have (#152).
                let loginState = actions.loginItem.state
                ToggleLine(label: "Launch at login",
                           isOn: Binding(get: { loginState.isOn },
                                         set: { actions.setLaunchAtLogin($0) }))
                    .id(actions.loginItemRevision)
                if loginState.needsUserApproval {
                    // Registered and parked. The app will NOT start at the next login while it sits
                    // here, and nothing else on screen would say so.
                    Text("macOS is waiting for you to allow this in System Settings, "
                        + "General, Login Items.")
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SectionCard("SOUND") {
                ToggleLine(label: "Start and stop cues",
                           isOn: Binding(get: { model.preferences.soundEnabled },
                                         set: { model.preferences.soundEnabled = $0 }))
                // What it does, in the user's terms. The cues are generated rather than sampled
                // (#172) - the tool this was matched to ships its own audio, and copying it into a
                // public repository would be redistributing someone else's assets.
                Text("A short tone when dictation starts, a lower one when it ends.")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ToggleLine(label: "Silence other audio",
                           isOn: Binding(get: { model.preferences.silenceWhileDictating },
                                         set: { model.preferences.silenceWhileDictating = $0 }))
                // Says WHY, because on a laptop the speakers are inches from the microphone and
                // whatever is playing becomes part of what the transcriber is asked to make sense of.
                Text("Mutes the Mac while you dictate, so music does not reach the microphone.")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionCard("CLEANUP") {
                ToggleLine(label: "Tidy transcripts",
                           isOn: Binding(get: { model.preferences.cleanupEnabled },
                                         set: { model.preferences.cleanupEnabled = $0 }))
                // The cost is stated because the choice is only informed if the user knows what
                // they are buying. These are measured numbers (#94), not a hedge: half of all
                // dictations pay a ~3.2 s model load, and the rest are near-instant.
                Text("On-device polish. Adds about 3 seconds to roughly half of dictations.")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let transcript = model.lastTranscript, !transcript.isEmpty {
                LastTranscriptCard(transcript: transcript, warning: model.lastCaptureWarning)
            }
        }
        .frame(width: 320)
        .background(Tokens.panel)
        // Recomputed on OPEN, not cached at launch. The user changes these in System Settings while
        // this menu is closed, so a launch-time value is stale exactly when they come back to check.
        //
        // The update probe is here for the same reason (#170) and it is the same bug: it ran once
        // from `onLaunch` and never again, so a menu opened days later drew its dot from a days-old
        // answer. This is the moment the user is looking at two of the three places that mark
        // lives. `UpdateCheckPolicy` rate-limits it - the menu gets opened constantly.
        .onAppear {
            model.refreshPermissionAdvice()
            actions.refreshUpdateAvailability()
        }
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
/// The hotkey chooser (#104).
///
/// A picker over `HotkeyBinding.selectable`, NOT a TermTile-style combo recorder. PushText binds a
/// bare held modifier, and PLAN.md 2.2 records why that is not interchangeable with a chord:
/// `RegisterEventHotKey` cannot express a bare modifier at all, and Secure Input filters
/// `keyDown`/`keyUp` while `flagsChanged` keeps flowing - so a bare modifier still dictates inside a
/// password field where a chord dies silently. Offering arbitrary combos would quietly trade that
/// away, and `selectable` already enumerates exactly the keys the event tap can observe.
/// The dictation key as a click-to-record field, matching TermTile's shortcut control.
///
/// Replaced a `Picker` (#128). A dropdown lists five names and makes you read them; a recorder lets
/// you answer "which key?" with the key itself, which is also the only way to find out whether the
/// one you want is even bindable.
private struct RecorderLine: View {
    let label: String
    let current: HotkeyBinding
    let onRecordingChange: (Bool) -> Void
    let onCapture: (HotkeyBinding) -> Void

    var body: some View {
        // `.center`, not `.firstTextBaseline` like the sibling rows: an NSView has no text
        // baseline for SwiftUI to align to, and asking for one dropped the field visibly below its
        // own label. Caught by rendering it, not by reading it.
        HStack(alignment: .center, spacing: Tokens.space) {
            Text(label)
                .font(Tokens.body)
                .foregroundStyle(Tokens.muted)
            Spacer(minLength: Tokens.space)
            HotkeyRecorder(current: current,
                           onRecordingChange: onRecordingChange,
                           onCapture: onCapture)
                .frame(width: 132, height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(current.name))
    }
}

private struct ToggleLine: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.space) {
            Text(label)
                .font(Tokens.body)
                .foregroundStyle(Tokens.muted)
            Spacer(minLength: Tokens.space)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(label))
    }
}

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

/// The Globe-key note (#190).
///
/// Deliberately quiet: `Tokens.muted`, no warning glyph. This describes a system setting the user may
/// have chosen on purpose - it is not a fault, and styling it like one taught the user that PushText
/// raises alarms about nothing.
///
/// **Built from the design system rather than by hand (#194).** The first version used a bare
/// `Button` for Dismiss, which had no hover and no cursor change, sitting beside a `LinkButton` that
/// has both - so one control looked alive and the other looked dead. `DESIGN.md` names the right one:
/// *"Ghost - GhostIconButton ... For inline/secondary controls: search-field x, chip-remove, inline
/// delete."* Colour-only, because `fill: true` is reserved for a roomy field-scoped control and this
/// glyph sits on a card.
///
/// The link uses `LinkButton`'s URL initializer rather than calling `NSWorkspace` by hand - the
/// component already does that, and it is the documented path.
private struct GlobeKeyNote: View {
    let action: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.space) {
            VStack(alignment: .leading, spacing: Tokens.micro) {
                Text("macOS also uses the Globe key for \(action).")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
                LinkButton("Keyboard Settings", url: Self.keyboardSettings,
                           systemImage: "gearshape")
                    .fixedSize()
            }
            Spacer(minLength: Tokens.micro)
            GhostIconButton(systemName: "xmark", action: onDismiss)
                .accessibilityLabel(Text("Dismiss this note"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let keyboardSettings = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
