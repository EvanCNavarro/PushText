import Foundation
import Observation
import PushTextCore
import PushTextKit

/// One editable line in the dictionary editor (#156).
///
/// Separate from `DictionaryEntry` because a row being EDITED is allowed to be incomplete - half a
/// rule is a normal intermediate state while typing - whereas an entry on disk is not.
@Observable
final class DictionaryRow: Identifiable {
    let id = UUID()
    var spoken: String
    var written: String

    init(spoken: String = "", written: String = "") {
        self.spoken = spoken
        self.written = written
    }
}

/// The dictionary editor's state and rules (#156).
///
/// Bobby asked for these files to be "editable in a popup proper ui". #154 made the file OPEN, which
/// is not the same thing: it handed the user a JSONL file in TextEdit and hoped.
///
/// Split from the view because the rules have right and wrong answers - what counts as an empty row,
/// what gets trimmed, what reaches disk - and none of that is testable through a SwiftUI form.
@Observable
@MainActor
final class DictionaryEditorModel {
    var rows: [DictionaryRow]
    private let store: any DictionaryStore

    init(store: any DictionaryStore) {
        self.store = store
        self.rows = store.load().map { DictionaryRow(spoken: $0.spoken, written: $0.written) }
    }

    func addRow() {
        rows.append(DictionaryRow())
    }

    func deleteRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }

    /// Writes the complete rows, in the user's order.
    ///
    /// A row needs BOTH halves. An empty spoken form is discarded by the store anyway, and an empty
    /// written form is worse than useless - it would rewrite the user's word to nothing, silently
    /// deleting text they had just dictated.
    ///
    /// Order is preserved because the file is the user's document. `CustomDictionary` sorts
    /// longest-first when it matches, so nothing depends on the order on disk.
    func save() {
        let entries = rows.compactMap { row -> DictionaryEntry? in
            let spoken = row.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            let written = row.written.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty, !written.isEmpty else { return nil }
            return DictionaryEntry(spoken: spoken, written: written)
        }
        store.save(entries)
    }
}
