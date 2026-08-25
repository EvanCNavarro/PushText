import MacFaceKit
import SwiftUI

/// The history viewer (#161).
///
/// A WINDOW rather than a popover, for the reason `DictionaryEditorView` records: the menu-bar
/// popover dismisses the moment focus moves, and the search field takes focus.
///
/// READ-ONLY, on purpose. History is a record of what the user said and what PushText typed; an
/// editable record is a worse record, and #97 established that history equals what was injected.
/// The only actions here are finding a transcript and copying it out.
struct HistoryViewerView: View {
    @Bindable var model: HistoryViewerModel
    let onOpenFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.space) {
            // Only when there is something to search. Rendering the never-recorded state showed a
            // field, a count and an Open File button over an empty list - three controls that
            // could not do anything, above a sentence explaining there was nothing there.
            if model.hasHistory { search }

            if let message = model.emptyMessage {
                empty(message)
            } else {
                transcripts
            }

            footer
        }
        .padding(Tokens.pad)
        .frame(minWidth: 460, minHeight: 320)
        .background(Tokens.panel)
    }

    private var search: some View {
        HStack(spacing: Tokens.space) {
            Image(systemName: "magnifyingglass")
                .font(Tokens.caption).foregroundStyle(Tokens.quiet)
            TextField("Search transcripts", text: $model.query)
                .textFieldStyle(.plain)
                .font(Tokens.body)
                .foregroundStyle(Tokens.text)
            if !model.query.isEmpty {
                GhostIconButton(systemName: "xmark.circle.fill") { model.query = "" }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Tokens.inset)
        .frame(height: Tokens.control)
        .background(RoundedRectangle(cornerRadius: Tokens.radius, style: .continuous)
            .fill(Tokens.field))
    }

    private var transcripts: some View {
        ScrollView {
            VStack(spacing: Tokens.micro) {
                ForEach(model.visible) { row in
                    TranscriptRow(row: row)
                }
            }
            .padding(.vertical, Tokens.micro)
        }
        .frame(maxHeight: .infinity)
    }

    /// Centred and quiet. The two messages differ because only one of them means the history was
    /// deleted - see `HistoryViewerModel.nothingRecorded`.
    private func empty(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(Tokens.body).foregroundStyle(Tokens.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var footer: some View {
        // Hidden entirely when nothing was ever recorded: `clear()` REMOVES the file, so there is
        // no file to open, and the count would repeat what the empty message already said.
        if model.hasHistory {
            HStack {
                if let label = model.countLabel {
                    Text(label)
                        .font(Tokens.caption).foregroundStyle(Tokens.muted)
                }
                Spacer()
                // LinkButton IS the right affordance here, unlike in the dictionary editor: this
                // hands the file to another application, so "this leaves the app" is what it does.
                //
                // A DOCUMENT glyph, not an arrow one. `arrow.up.forward.app` put a second arrow in
                // front of the trailing arrow LinkButton already draws - visible immediately in a
                // screenshot and invisible in the source.
                LinkButton("Open File", systemImage: "doc.text", action: onOpenFile)
                    .fixedSize()
            }
        }
    }
}

/// One transcript. The text is selectable so a user can take part of a line without the copy
/// button, which is what a person tries first.
private struct TranscriptRow: View {
    let row: HistoryViewerModel.Row
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.micro) {
            HStack(spacing: Tokens.space) {
                Text(row.timestamp)
                    .font(Tokens.caption).foregroundStyle(Tokens.muted)
                Text(row.duration)
                    .font(Tokens.caption).foregroundStyle(Tokens.quiet)
                Spacer()
                GhostIconButton(systemName: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .accessibilityLabel(copied ? "Copied" : "Copy transcript")
            }
            Text(highlighted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Tokens.inset)
        .background(RoundedRectangle(cornerRadius: Tokens.radius, style: .continuous)
            .fill(Tokens.row))
    }

    /// The transcript with the search hits marked (#167).
    ///
    /// TWO cues, not one. The background is the update indicator's orange at low opacity, and the
    /// matched words also go semibold - colour alone must not be the only thing carrying meaning
    /// (WCAG 1.4.1), and on a menu-bar utility someone may well be looking at this through a
    /// colour filter or on a badly calibrated external display.
    ///
    /// Measured rather than eyeballed: `Tokens.warning` at 0.25 over `Tokens.row` composites to
    /// rgb(82, 63, 41), against which `Tokens.text` sits at **8.99:1** - past WCAG AAA for body
    /// text, and the reason the text stays near-white instead of turning orange. Orange text on an
    /// orange wash would have been the obvious move and the worse one.
    private var highlighted: AttributedString {
        var attributed = AttributedString(row.text)
        attributed.font = Tokens.body
        attributed.foregroundColor = Tokens.text
        for range in row.matches {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else {
                continue
            }
            attributed[lower..<upper].backgroundColor = Self.matchBackground
            attributed[lower..<upper].font = Self.matchFont
        }
        return attributed
    }

    /// The update indicator's colour, softened. Deliberately the same hue: both marks mean "the
    /// thing you are looking for is here", and a second accent colour would be a second vocabulary
    /// for the user to learn.
    private static let matchBackground = Tokens.warning.opacity(0.25)
    private static let matchFont = Font.system(size: 13, weight: .semibold)

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.text, forType: .string)
        copied = true
        // The checkmark is the whole feedback - a copy that looks identical before and after leaves
        // the user pressing it twice.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
