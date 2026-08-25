import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// The file-backed half of history (#10).
///
/// The codec is covered in Core with no filesystem. What only a real file can show is that appends
/// ACCUMULATE rather than overwrite, that concurrent appends do not interleave into a torn line,
/// and that the cap is applied.
@Suite("JSONL history store")
struct JSONLHistoryStoreTests {

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pushtext-history-\(UUID().uuidString).jsonl")
    }

    private func record(_ text: String) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
                      durationSeconds: 1)
    }

    @Test("Appends accumulate instead of replacing the file")
    func appendsAccumulate() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLHistoryStore(url: url)

        store.append(record("first"))
        store.append(record("second"))
        store.append(record("third"))

        #expect(store.load().map(\.text) == ["first", "second", "third"])
    }

    @Test("A fresh store reads as empty rather than failing")
    func missingFileIsEmpty() {
        #expect(JSONLHistoryStore(url: temporaryURL()).load().isEmpty)
    }

    @Test("clear() removes the history")
    func clearEmptiesIt() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLHistoryStore(url: url)
        store.append(record("gone"))

        store.clear()

        #expect(store.load().isEmpty)
    }

    /// The menu's Delete History removes the FILE, not its contents, so the very next dictation
    /// appends to a path that no longer exists. Nothing covered that sequence: every other test
    /// here either appends to a fresh path or clears and stops.
    ///
    /// What only this test catches, measured rather than asserted. Make `clear()` leave the path
    /// unwritable - a plausible shape for a future "delete more thoroughly" change - and the other
    /// five tests all still pass, `clear() removes the history` included, because the path does
    /// read as empty afterwards. It reads as empty forever, which is the part that matters: the
    /// user deletes their history once and PushText silently stops recording, with a menu that
    /// still says it is listening.
    @Test("Recording survives a delete instead of silently stopping")
    func appendRecoversAfterClear() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLHistoryStore(url: url)
        store.append(record("before the delete"))

        store.clear()
        store.append(record("after the delete"))

        #expect(store.load().map(\.text) == ["after the delete"],
                "history stopped recording once it had been deleted")
    }

    @Test("The cap keeps the most recent entries")
    func capKeepsNewest() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLHistoryStore(url: url, limit: 3)
        for index in 1...6 { store.append(record("\(index)")) }

        #expect(store.load().map(\.text) == ["4", "5", "6"])
    }

    /// Interleaving is a property that exists only DURING the operation - it leaves no trace in a
    /// file written one append at a time, so a sequential test is blind to it by construction.
    /// Twenty concurrent writers either produce twenty intact lines or they do not.
    @Test("Concurrent appends do not tear each other's lines")
    func concurrentAppendsStayIntact() async {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONLHistoryStore(url: url)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask { store.append(HistoryRecord(text: "line-\(index)",
                                                           recordedAt: Date(),
                                                           durationSeconds: 1)) }
            }
        }

        let loaded = store.load()
        #expect(loaded.count == 20, "expected 20 intact records, got \(loaded.count)")
        #expect(Set(loaded.map(\.text)).count == 20, "records were lost or duplicated")
    }
}
