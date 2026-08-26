import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// Bounding the history file so read cost stops growing (#222).
///
/// Measured before the fix: `load()` costs 0.34 ms at 23 records, 6.19 ms at 500, 25.15 ms at 5,000
/// and 88.10 ms at 20,000 - scaling with the FILE while the decoded count stays pinned at 500,
/// because the trim happened in memory and was never written back.
@Suite("History compaction")
struct HistoryCompactionTests {

    private func temporaryURL() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("compact-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.jsonl")
    }

    private func record(_ text: String, at seconds: TimeInterval) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: seconds),
                      durationSeconds: 1)
    }

    /// Fills a file past the compaction threshold, writing directly so the store's own append path
    /// is not what created the oversize.
    private func fill(_ url: URL, records: Int) throws {
        var text = ""
        let padding = String(repeating: "x", count: 400)
        for index in 0..<records {
            text += try HistoryRecord.encodeLine(record("\(index) \(padding)", at: Double(index)))
            text += "\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The defect: the file grew forever because the trim only ever happened in memory.
    @Test("An oversized file is compacted when the next dictation is appended")
    func oversizedFileIsCompacted() throws {
        let url = temporaryURL()
        let store = JSONLHistoryStore(url: url, limit: 50)
        try fill(url, records: 4000)
        let before = try #require(HistoryFileStamp.read(url)).size
        #expect(before > JSONLHistoryStore.compactionThreshold, "the fixture must exceed the threshold")

        store.append(record("the newest one", at: 99_999))

        let after = try #require(HistoryFileStamp.read(url)).size
        #expect(after < before, "the file should have shrunk")
        // Bounded by the cap, not by whatever it happened to reach.
        #expect(store.load().count <= 51)
    }

    /// The trap this fix could easily introduce: `trim` joins lines WITHOUT a trailing newline, so a
    /// compaction that forgets one makes the next append land on the same line and silently merges
    /// two dictations into one unparseable record.
    @Test("A dictation appended after compaction is a separate record")
    func appendAfterCompactionStaysSeparate() throws {
        let url = temporaryURL()
        let store = JSONLHistoryStore(url: url, limit: 50)
        try fill(url, records: 4000)

        store.append(record("triggers compaction", at: 99_998))
        store.append(record("the one after", at: 99_999))

        // A merge makes the joined line unparseable, so `decodeFile` SKIPS it: the count drops to 49
        // and the last record is the pre-compaction one. Both assertions are about that, not about
        // arithmetic on the cap - `load()` can never exceed the limit, so "+1" was never possible.
        let loaded = store.load()
        #expect(loaded.count == 50, "a merged line would be skipped, leaving 49")
        #expect(loaded.last?.text == "the one after")
    }

    /// Compaction must keep the NEWEST records. Trimming the wrong end silently discards exactly what
    /// the user is most likely to want back.
    @Test("Compaction keeps the newest records")
    func compactionKeepsNewest() throws {
        let url = temporaryURL()
        let store = JSONLHistoryStore(url: url, limit: 50)
        try fill(url, records: 4000)

        store.append(record("NEWEST", at: 99_999))

        // Read the FILE, not load(): load() has always trimmed to the newest in memory, so asserting
        // on it passes with no compaction at all and tests the wrong thing entirely.
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk.contains("NEWEST"))
        #expect(onDisk.contains("3999 "), "the newest fixture record should survive")
        #expect(!onDisk.contains("\"0 xxx"), "the oldest should be gone from DISK, not just hidden")
    }

    /// A file under the threshold must NOT be rewritten. Compacting on every append would reintroduce
    /// the whole-file write that JSONL was chosen to avoid.
    @Test("A small file is left alone")
    func smallFileIsNotRewritten() throws {
        let url = temporaryURL()
        let store = JSONLHistoryStore(url: url, limit: 50)
        store.append(record("first", at: 1))
        let before = try #require(HistoryFileStamp.read(url))

        store.append(record("second", at: 2))

        let after = try #require(HistoryFileStamp.read(url))
        // Same inode: appended in place rather than replaced by an atomic write.
        #expect(after.inode == before.inode)
        #expect(store.load().count == 2)
    }
}
