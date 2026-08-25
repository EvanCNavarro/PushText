import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Editing the dictionary in the app instead of in TextEdit (#156).
///
/// Bobby: *"what about those things being editable in a popup proper ui."* #154 made the file OPEN;
/// it did not make it editable in any sense a user would call an interface - it handed them a JSONL
/// file and hoped.
///
/// The model is separated from the view because the rules have right and wrong answers - what counts
/// as an empty row, what happens to duplicates, what reaches disk - and none of that is testable
/// through a SwiftUI form.
@Suite("Dictionary editor model")
@MainActor
struct DictionaryEditorModelTests {

    /// `@unchecked` because the protocol is Sendable and this records calls for assertions; every
    /// use is on the main actor inside one test.
    private final class SpyStore: DictionaryStore, @unchecked Sendable {
        var entries: [DictionaryEntry] = []
        var saves: [[DictionaryEntry]] = []
        func load() -> [DictionaryEntry] { entries }
        func save(_ entries: [DictionaryEntry]) { saves.append(entries); self.entries = entries }
    }

    @Test("Existing entries are loaded for editing")
    func loadsExisting() {
        let store = SpyStore()
        store.entries = [DictionaryEntry(spoken: "push text", written: "PushText")]
        let model = DictionaryEditorModel(store: store)
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.spoken == "push text")
        #expect(model.rows.first?.written == "PushText")
    }

    /// A new row starts blank, and a blank row is NOT written to disk - the store already discards
    /// entries with an empty spoken form, and saving them would grow the file with nothing.
    @Test("A blank row is never saved")
    func blankRowsAreNotSaved() {
        let store = SpyStore()
        let model = DictionaryEditorModel(store: store)
        model.addRow()
        model.save()

        #expect(store.saves.last?.isEmpty == true, "a blank row reached disk")
    }

    /// A row with a spoken form but no written form is also incomplete: it would rewrite the user's
    /// word to nothing, silently deleting text they dictated.
    @Test("A row with no written form is never saved")
    func halfFilledRowsAreNotSaved() {
        let store = SpyStore()
        let model = DictionaryEditorModel(store: store)
        model.addRow()
        model.rows[0].spoken = "push text"
        model.save()

        #expect(store.saves.last?.isEmpty == true,
                "an entry with an empty written form would erase what the user said")
    }

    @Test("A complete row is saved")
    func completeRowIsSaved() {
        let store = SpyStore()
        let model = DictionaryEditorModel(store: store)
        model.addRow()
        model.rows[0].spoken = "push text"
        model.rows[0].written = "PushText"
        model.save()

        #expect(store.saves.last == [DictionaryEntry(spoken: "push text", written: "PushText")])
    }

    /// Whitespace is trimmed, because "push text " and "push text" are the same thing to a person and
    /// a trailing space in the spoken form would stop the rule ever matching.
    @Test("Surrounding whitespace is trimmed before saving")
    func whitespaceIsTrimmed() {
        let store = SpyStore()
        let model = DictionaryEditorModel(store: store)
        model.addRow()
        model.rows[0].spoken = "  push text  "
        model.rows[0].written = "  PushText  "
        model.save()

        #expect(store.saves.last == [DictionaryEntry(spoken: "push text", written: "PushText")])
    }

    @Test("Deleting a row removes it from the file")
    func deletingSaves() {
        let store = SpyStore()
        store.entries = [DictionaryEntry(spoken: "a", written: "A"),
                         DictionaryEntry(spoken: "b", written: "B")]
        let model = DictionaryEditorModel(store: store)
        model.deleteRow(at: 0)
        model.save()

        #expect(store.saves.last == [DictionaryEntry(spoken: "b", written: "B")])
    }

    /// ORDER is meaningful: `CustomDictionary` sorts longest-first when matching, but the file is the
    /// user's document and their arrangement should come back the way they left it.
    @Test("Row order is preserved")
    func orderIsPreserved() {
        let store = SpyStore()
        let model = DictionaryEditorModel(store: store)
        for (spoken, written) in [("one", "1"), ("two", "2"), ("three", "3")] {
            model.addRow()
            model.rows[model.rows.count - 1].spoken = spoken
            model.rows[model.rows.count - 1].written = written
        }
        model.save()

        #expect(store.saves.last?.map(\.spoken) == ["one", "two", "three"])
    }
}
