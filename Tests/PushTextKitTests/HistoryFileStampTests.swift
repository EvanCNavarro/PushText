import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// The cheap "has the file changed" check the open viewer polls (#202).
@Suite("History file stamp")
struct HistoryFileStampTests {

    private func temporaryFile() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stamp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.jsonl")
    }

    private func record(_ text: String) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: 100), durationSeconds: 1)
    }

    @Test("No file is a stamp of its own, not an error")
    func absentFile() {
        #expect(HistoryFileStamp.read(temporaryFile()) == nil)
    }

    /// The case the whole feature rests on: a dictation is appended and the poller must see it.
    @Test("Appending changes the stamp")
    func appendChangesStamp() {
        let url = temporaryFile()
        let store = JSONLHistoryStore(url: url)
        store.append(record("first"))
        let before = store.changeStamp()

        store.append(record("second"))

        #expect(before != nil)
        #expect(store.changeStamp() != before)
    }

    @Test("An untouched file keeps the same stamp")
    func unchangedFileIsStable() {
        let url = temporaryFile()
        let store = JSONLHistoryStore(url: url)
        store.append(record("first"))

        #expect(store.changeStamp() == store.changeStamp())
    }

    /// The reason `inode` is in there. Delete History removes the file; the next dictation recreates
    /// it. Written back at the SAME LENGTH, size and modification date can both land unchanged - and
    /// a stamp built from those two alone would call a wiped history identical to the old one.
    @Test("Clearing and rewriting the same bytes is still a change")
    func clearAndRecreateIsAChange() throws {
        let url = temporaryFile()
        let store = JSONLHistoryStore(url: url)
        store.append(record("same"))
        let before = try #require(store.changeStamp())

        store.clear()
        store.append(record("same"))
        let after = try #require(store.changeStamp())

        // The size really is identical - otherwise this test would pass on the size field alone and
        // prove nothing about the inode.
        #expect(after.size == before.size)
        #expect(after != before)
        #expect(after.inode != before.inode)
    }
}

/// The store telling an open viewer that the history moved (#202).
///
/// This is the signal the whole fix rides on: without it the window is a snapshot again, and every
/// model-level test still passes because they call `refresh()` themselves.
@Suite("History change notification")
struct HistoryChangeNotificationTests {

    private func temporaryStore() -> JSONLHistoryStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notify-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return JSONLHistoryStore(url: directory.appendingPathComponent("history.jsonl"))
    }

    private func record(_ text: String) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: 100), durationSeconds: 1)
    }

    /// Counts posts on the calling thread. Deliberately not `confirmation()`: what matters is the
    /// count, and a post that never arrives should fail as a number rather than time out.
    private func countingPosts(from store: JSONLHistoryStore, _ body: () -> Void) -> Int {
        var count = 0
        // Narrowed to THIS store. Suites run in parallel and every one of them appends to a history
        // of its own, so an unfiltered observer counts theirs too - measured at four posts for one
        // append before the notification carried its sender.
        let token = NotificationCenter.default.addObserver(
            forName: .historyDidChange, object: store, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return count
    }

    @Test("Appending a dictation announces the change")
    func appendAnnounces() {
        let store = temporaryStore()

        #expect(countingPosts(from: store) { store.append(record("first")) } == 1)
    }

    /// Delete History has to reach an open window too, or it keeps showing transcripts that are
    /// gone from disk.
    @Test("Clearing history announces the change")
    func clearAnnounces() {
        let store = temporaryStore()
        store.append(record("first"))

        #expect(countingPosts(from: store) { store.clear() } == 1)
    }

    /// The announcement must not be made while the store's own lock is held: an observer that reads
    /// the store synchronously - which is exactly what the viewer does - would deadlock on it.
    @Test("An observer can read the store from inside the notification")
    func observerCanReadTheStore() {
        let store = temporaryStore()
        var readBack: [HistoryRecord] = []
        let token = NotificationCenter.default.addObserver(
            forName: .historyDidChange, object: store, queue: nil
        ) { _ in readBack = store.load() }
        defer { NotificationCenter.default.removeObserver(token) }

        store.append(record("first"))

        #expect(readBack.map(\.text) == ["first"])
    }
}

/// Keeping Sparkle out of a probe process (#202).
@Suite("Probe process detection")
struct ProbeProcessTests {

    @Test("A plain environment is not a probe")
    func plainEnvironment() {
        #expect(ProbeActivation.isProbeProcess(environment: ["HOME": "/Users/someone"]) == false)
    }

    @Test("An activated probe is a probe")
    func activatedProbe() {
        #expect(ProbeActivation.isProbeProcess(environment: ["PUSHTEXT_MENU_PROBE": "1"]))
    }

    /// A process pointed at a scratch history file is not the user's app either.
    @Test("A redirected history file counts")
    func redirectedHistory() {
        #expect(ProbeActivation.isProbeProcess(environment: ["PUSHTEXT_HISTORY_FILE": "/tmp/x"]))
    }

    /// An empty value is how an unset variable arrives through a shell that exported it blank, and
    /// it must not switch the app into probe behaviour.
    @Test("An empty value is not an activation")
    func emptyValue() {
        #expect(ProbeActivation.isProbeProcess(environment: ["PUSHTEXT_MENU_PROBE": ""]) == false)
    }
}
