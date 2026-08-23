import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// Where the custom dictionary's entries come from (#82).
///
/// `CustomDictionary(entries:)` has existed since #9 with 15 tests and no source of entries, so
/// wiring it would have applied an empty dictionary to every transcript. This is the missing input.
///
/// Same JSONL shape as history (#10) and deliberately NOT the same codec: two record types with
/// different fields behind one generic would be a contorted abstraction for a five-line encoder.
@Suite("Dictionary store")
struct DictionaryStoreTests {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pushtext-dict-\(UUID().uuidString).jsonl")
    }

    @Test("Entries round-trip through the file")
    func roundTrip() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLDictionaryStore(url: url)

        store.save([DictionaryEntry(spoken: "push text", written: "PushText"),
                    DictionaryEntry(spoken: "in vela", written: "Invela")])

        #expect(store.load() == [DictionaryEntry(spoken: "push text", written: "PushText"),
                                 DictionaryEntry(spoken: "in vela", written: "Invela")])
    }

    @Test("A missing file is an empty dictionary rather than a failure")
    func missingFileIsEmpty() {
        #expect(JSONLDictionaryStore(url: temporaryURL()).load().isEmpty)
    }

    /// The user edits this file by hand, so a typo in one line is the EXPECTED failure - not an
    /// exotic one. It must cost that line, never the whole dictionary.
    @Test("A hand-edited broken line costs that line only")
    func brokenLineIsSkipped() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let good = #"{"spoken":"push text","written":"PushText"}"#
        let alsoGood = #"{"spoken":"in vela","written":"Invela"}"#
        try [good, "{oops the user broke this", alsoGood].joined(separator: "\n")
            .write(to: url, atomically: true, encoding: .utf8)

        #expect(JSONLDictionaryStore(url: url).load().map(\.written) == ["PushText", "Invela"])
    }

    /// An entry that rewrites nothing is a waste of a rule, but an entry with an EMPTY spoken form
    /// is worse: it would match everywhere. Dropped on load rather than trusted.
    @Test("An entry with an empty spoken form is discarded")
    func emptySpokenIsDiscarded() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try [#"{"spoken":"","written":"NOPE"}"#, #"{"spoken":"ok","written":"OK"}"#]
            .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        #expect(JSONLDictionaryStore(url: url).load().map(\.written) == ["OK"])
    }

    /// Seeding must not change anyone's dictation. An example whose spoken and written forms differ
    /// would silently rewrite text the user never asked to rewrite.
    @Test("The seeded example file is a no-op dictionary")
    func seedIsHarmless() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLDictionaryStore(url: url)

        store.createWithExampleIfMissing()

        let entries = store.load()
        #expect(!entries.isEmpty, "the seed must show the format, or the file teaches nothing")
        for entry in entries {
            #expect(entry.spoken == entry.written,
                    "seeded entry '\(entry.spoken)' -> '\(entry.written)' would rewrite real text")
        }
        #expect(CustomDictionary(entries: entries).apply(to: "untouched text") == "untouched text")
    }

    @Test("Seeding never overwrites entries the user already has")
    func seedDoesNotClobber() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLDictionaryStore(url: url)
        store.save([DictionaryEntry(spoken: "mine", written: "MINE")])

        store.createWithExampleIfMissing()

        #expect(store.load() == [DictionaryEntry(spoken: "mine", written: "MINE")])
    }
}
