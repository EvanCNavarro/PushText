import Testing
import Foundation
@testable import PushText
import PushTextCore
import PushTextKit

/// The viewer refreshing while it is open (#202).
///
/// Bobby left the window open, dictated, and the new transcript never appeared - the window had
/// always been a snapshot taken at open, and only REOPENING it re-read the file.
@Suite("History viewer refresh")
@MainActor
struct HistoryViewerRefreshTests {

    /// A store that can change under an open viewer, and that counts how often it was read - the
    /// count is what proves the poller is not decoding the whole file every tick.
    private final class ChangingStore: HistoryReading {
        var records: [HistoryRecord]
        var stamp: HistoryFileStamp?
        private(set) var loads = 0

        init(_ records: [HistoryRecord]) {
            self.records = records
            self.stamp = HistoryFileStamp(size: records.count, modified: Date(timeIntervalSince1970: 1),
                                          inode: 1)
        }

        func load() -> [HistoryRecord] {
            loads += 1
            return records
        }

        func changeStamp() -> HistoryFileStamp? { stamp }

        /// Appends the way the real store does: the file grows, so the stamp moves.
        func append(_ record: HistoryRecord) {
            records.append(record)
            stamp = HistoryFileStamp(size: records.count, modified: Date(timeIntervalSince1970: 2),
                                     inode: 1)
        }

        /// `clear()` REMOVES the file, which is why the stamp goes away rather than changing.
        func clear() {
            records = []
            stamp = nil
        }
    }

    private func record(_ text: String, at seconds: TimeInterval) -> HistoryRecord {
        HistoryRecord(text: text, recordedAt: Date(timeIntervalSince1970: seconds),
                      durationSeconds: 1)
    }

    /// The reported defect.
    @Test("A dictation made while the window is open appears on the next refresh")
    func picksUpANewDictation() {
        let store = ChangingStore([record("first", at: 100)])
        let subject = HistoryViewerModel(store: store)
        #expect(subject.visible.map(\.text) == ["first"])

        store.append(record("second", at: 200))
        subject.refresh()

        #expect(subject.visible.map(\.text) == ["second", "first"])
    }

    /// A list that reloads and silently empties the search box is the same bug in different
    /// clothes: the user is mid-search, a dictation lands, and their query disappears.
    @Test("Refreshing keeps what the user typed")
    func keepsTheQuery() {
        let store = ChangingStore([record("send the invoice", at: 100)])
        let subject = HistoryViewerModel(store: store)
        subject.query = "invoice"

        store.append(record("book a table", at: 200))
        subject.refresh()

        #expect(subject.query == "invoice")
        #expect(subject.visible.map(\.text) == ["send the invoice"])
    }

    /// Delete History removes the file underneath an open window.
    @Test("Clearing history empties the open window")
    func noticesHistoryBeingDeleted() {
        let store = ChangingStore([record("first", at: 100)])
        let subject = HistoryViewerModel(store: store)

        store.clear()
        subject.refresh()

        #expect(subject.visible.isEmpty)
        #expect(subject.hasHistory == false)
        // The message has to be the DELETED one, not "no dictation matches that search".
        #expect(subject.emptyMessage == HistoryViewerModel.nothingRecorded)
    }

    /// The reason the stamp exists. Without it the poller would decode up to five hundred JSON
    /// lines every second to discover that nothing had happened.
    @Test("An unchanged file is not re-read")
    func doesNotRereadAnUnchangedFile() {
        let store = ChangingStore([record("first", at: 100)])
        let subject = HistoryViewerModel(store: store)
        let after = store.loads

        subject.refresh()
        subject.refresh()
        subject.refresh()

        #expect(store.loads == after)
        #expect(after == 1)
    }

    /// A row's identity must not move when a newer dictation arrives.
    ///
    /// SwiftUI keys per-row `@State` off it, and the copy button's checkmark is per-row state. This
    /// is stated as two models rather than a refresh on purpose: it is a property of the numbering
    /// itself, and it should hold however the second record got there.
    @Test("A transcript keeps its id when a newer one arrives")
    func rowIdentitySurvivesAnAppend() throws {
        let older = record("first", at: 100)
        let before = HistoryViewerModel(records: [older])
        let after = HistoryViewerModel(records: [older, record("second", at: 200)])

        let idBefore = try #require(before.visible.first { $0.text == "first" }?.id)
        let idAfter = try #require(after.visible.first { $0.text == "first" }?.id)

        #expect(idBefore == idAfter)
        // And the new one is genuinely distinct rather than everything collapsing onto one id.
        #expect(after.visible.map(\.id).count == Set(after.visible.map(\.id)).count)
    }
}

/// The seam between the real store and the viewer's read protocol (#202).
///
/// Split out because it is where the fix FAILED on the real path while every model test above was
/// green: `HistoryReading` carries a default `changeStamp()` returning nil for the fixtures, and a
/// real store whose concrete method does not bind as the witness would silently take that default -
/// making every tick compare nil to nil, find no change, and never re-read. Identical behaviour to
/// having no refresh at all, and invisible to a test that supplies its own double.
@Suite("History store as a viewer reader")
@MainActor
struct HistoryStoreReadingTests {

    @Test("The real store reports a stamp THROUGH the viewer's protocol")
    func realStoreStampsThroughTheProtocol() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reading-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = JSONLHistoryStore(url: directory.appendingPathComponent("history.jsonl"))
        store.append(HistoryRecord(text: "first", recordedAt: Date(timeIntervalSince1970: 100),
                                   durationSeconds: 1))

        // Deliberately through the existential, which is how the viewer holds it.
        let reader: any HistoryReading = store

        #expect(reader.changeStamp() != nil)
    }
}
