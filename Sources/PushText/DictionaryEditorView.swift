import MacFaceKit
import SwiftUI

/// The dictionary editor (#156).
///
/// A WINDOW, not a popover. The menu-bar popover dismisses the moment focus moves, and a text field
/// takes focus - so an editor inside it would close on the first keystroke. TermTile learned the same
/// thing about its uninstall alerts and runs them in their own window for the same reason.
///
/// Saves as you type. Only complete rows reach disk, so a half-typed rule is never written, and
/// nothing is lost if the window is closed without ceremony - which is what a person does with a
/// settings window.
struct DictionaryEditorView: View {
    @Bindable var model: DictionaryEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.space) {
            header

            ScrollView {
                VStack(spacing: Tokens.micro) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        DictionaryRowView(row: row) {
                            model.deleteRow(at: index)
                            model.save()
                        } onEdit: {
                            model.save()
                        }
                    }
                }
                .padding(.vertical, Tokens.micro)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(Tokens.pad)
        .frame(minWidth: 460, minHeight: 320)
        .background(Tokens.panel)
    }

    private var header: some View {
        // No title here: the WINDOW is titled "Custom Dictionary" and repeating it in the content
        // said the same thing twice, which rendering made obvious.
        Text("What you say on the left, what PushText types on the right. Matching ignores case.")
            .font(Tokens.caption).foregroundStyle(Tokens.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            // PrimaryButton, not LinkButton: LinkButton is the EXTERNAL-LINK affordance - it
            // stretches to fill and draws a trailing arrow, which read as "this leaves the app".
            // Caught by rendering it.
            PrimaryButton("Add Entry", systemImage: "plus") {
                model.addRow()
            }
            .fixedSize()
            Spacer()
            // Nothing to save explicitly - saying so is kinder than an inert Save button that
            // implies the opposite about everything typed before it was pressed.
            Text(model.rows.isEmpty ? "No entries yet" : "Saved automatically")
                .font(Tokens.caption).foregroundStyle(Tokens.muted)
        }
    }
}

/// One editable rule.
private struct DictionaryRowView: View {
    @Bindable var row: DictionaryRow
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Tokens.space) {
            field("Spoken", text: $row.spoken)
            Image(systemName: "arrow.right")
                .font(Tokens.caption).foregroundStyle(Tokens.muted)
            field("Typed", text: $row.written)
            GhostIconButton(systemName: "trash", action: onDelete)
                .accessibilityLabel("Delete entry")
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(Tokens.body)
            .foregroundStyle(Tokens.text)
            .padding(.horizontal, Tokens.micro)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Tokens.radius, style: .continuous)
                .fill(Tokens.field))
            .onChange(of: text.wrappedValue) { _, _ in onEdit() }
    }
}
