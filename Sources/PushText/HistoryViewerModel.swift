import Foundation
import PushTextCore
import PushTextKit

/// The searchable history viewer (#161).
///
/// Separated from the view for the same reason `DictionaryEditorModel` is: these are questions with
/// right and wrong answers - which end of the file to open on, what a stray space in the search box
/// means, whether "nothing found" and "nothing recorded" are the same sentence - and a SwiftUI body
/// is where right and wrong answers go to hide.
@MainActor @Observable
final class HistoryViewerModel {

    /// Two different facts, deliberately worded so they can never be confused for each other. One
    /// of them means the user's history was deleted; the other means they typed a word that is not
    /// in it. Showing the wrong one is the failure this pair exists to prevent.
    static let nothingRecorded = "No dictations recorded yet."
    static let nothingMatched = "No dictation matches that search."

    /// One transcript, with its metadata already turned into something readable. The formatting
    /// lives here rather than in the view so it can be asserted on.
    struct Row: Identifiable {
        /// Counted from the OLDEST record, so it does not move when a new dictation arrives.
        ///
        /// SwiftUI keys per-row `@State` off this, and the copy button's checkmark is per-row
        /// state. Numbering from the newest end - which is what the list is DISPLAYED in - would
        /// renumber every row on each append, and with the window now refreshing live (#202) a tick
        /// showing "Copied" would jump to whatever transcript had taken that position.
        let id: Int
        let record: HistoryRecord
        let timestamp: String
        let duration: String
        /// Where the query matched, for the view to highlight. Empty when nothing is being searched.
        let matches: [Range<String.Index>]
        var text: String { record.text }
    }

    var query: String = ""

    /// Oldest-first, exactly as the file holds it. `visible` reverses for display; keeping the
    /// stored order is what lets a row's identity survive a new dictation arriving - see `Row.id`.
    private var records: [HistoryRecord]

    /// Kept so the window can re-read while it is open (#202), and `nil` for the fixtures that are
    /// constructed from records directly.
    @ObservationIgnored private var store: (any HistoryReading)?

    /// The version of the file the current `records` came from.
    @ObservationIgnored private var stamp: HistoryFileStamp?

    init(records: [HistoryRecord]) {
        self.records = records
    }

    /// Reads the store, so the window always shows what is on disk rather than a cached copy.
    convenience init(store: any HistoryReading) {
        // Stamp BEFORE load, and the order is load-bearing. Stamping afterwards would mean a
        // dictation landing between the two calls gets a stamp that already accounts for it while
        // the records do not - and every later tick would then compare equal and never re-read it.
        // Stamping first can only cost one redundant reload, which is the harmless direction.
        let stamp = store.changeStamp()
        self.init(records: store.load())
        self.store = store
        self.stamp = stamp
    }

    /// Re-reads the store if the file changed since the last look (#202).
    ///
    /// Bobby left the window open, dictated, and watched nothing appear. The window had always been
    /// a snapshot taken at open - the comment above `HistoryViewerWindow.show` even named a stale
    /// viewer as the thing to avoid, and then only handled REOPENING it.
    func refresh() {
        guard let store else { return }
        let current = store.changeStamp()
        guard current != stamp else { return }
        stamp = current
        records = store.load()
    }

    var visible: [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Numbered BEFORE filtering, so a transcript keeps its identity as the query changes.
        // Copy the top row, type in the search box, and a filtered-list numbering would put the
        // tick on whatever is now on top. `reversed()` is display order only - the numbers come
        // from the file's own order, which is the half that survives an append.
        return records.enumerated().reversed().compactMap { index, record -> Row? in
            var matches: [Range<String.Index>] = []
            if !needle.isEmpty {
                // `TranscriptSearch` searches the TEXT only. Searching the record's storage would
                // let "2026" match every dictation from this year while matching nothing anyone
                // actually said.
                guard let hit = TranscriptSearch.match(query: needle, in: record.text) else {
                    return nil
                }
                matches = hit.ranges
            }
            return Row(id: index, record: record,
                       timestamp: Self.timestamp.string(from: record.recordedAt),
                       duration: Self.duration(record.durationSeconds),
                       matches: matches)
        }
    }

    /// Whether anything was ever recorded - which is NOT the same as whether anything is visible.
    ///
    /// Found by rendering: a history with nothing in it drew a search field, a footer count and an
    /// Open File button, and none of the three could do anything. A search that found nothing is
    /// the opposite case, and has to keep the field the user needs to undo their query.
    var hasHistory: Bool { !records.isEmpty }

    /// `nil` when a message already says it. "0 dictations" sitting under the words "No dictations
    /// recorded yet" is the same fact twice, and the message says it better.
    var countLabel: String? {
        let shown = visible.count
        guard shown > 0 else { return nil }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return shown == 1 ? "1 dictation" : "\(shown) dictations"
        }
        return shown == 1 ? "1 match" : "\(shown) matches"
    }

    /// `nil` when there is something to show - a list with results must never also claim to be
    /// empty.
    var emptyMessage: String? {
        guard visible.isEmpty else { return nil }
        return records.isEmpty ? Self.nothingRecorded : Self.nothingMatched
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// One decimal place. Dictations are seconds long, so minutes would be noise and whole seconds
    /// would round a two-second utterance to the same number as a one-and-a-half second one.
    private static func duration(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}

/// The half of `HistoryStore` a reader needs. Narrowed so the viewer cannot append or clear: it is
/// a record, and a viewer holding the ability to rewrite it is one mistake away from doing so.
protocol HistoryReading {
    func load() -> [HistoryRecord]
    /// What the reader compares to decide whether `load()` would say anything new (#202).
    func changeStamp() -> HistoryFileStamp?
}

extension HistoryReading {
    /// A reader with nothing behind it never changes. The probe fixtures are fixed sets of records,
    /// so `nil` here is the truth about them rather than a stub - and it stays `nil` on every tick,
    /// which is what stops them from re-reading something that cannot move.
    func changeStamp() -> HistoryFileStamp? { nil }
}

/// The viewer only ever reads (#161).
extension JSONLHistoryStore: HistoryReading {}
