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
        let id: Int
        let record: HistoryRecord
        let timestamp: String
        let duration: String
        var text: String { record.text }
    }

    var query: String = ""

    private let records: [HistoryRecord]

    init(records: [HistoryRecord]) {
        // Reversed once, here. The file is appended to, so it is oldest-first; a viewer that opened
        // in that order would land on the user's oldest dictation and bury today's under the five
        // hundred the store keeps.
        self.records = records.reversed()
    }

    /// Reads the store, so the window always shows what is on disk rather than a cached copy.
    convenience init(store: any HistoryReading) {
        self.init(records: store.load())
    }

    var visible: [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty
            ? records
            // Only `text`. Searching the record's storage would let "2026" match every dictation
            // from this year while matching nothing anyone actually said.
            : records.filter { $0.text.range(of: needle, options: .caseInsensitive) != nil }
        return matched.enumerated().map { index, record in
            Row(id: index, record: record,
                timestamp: Self.timestamp.string(from: record.recordedAt),
                duration: Self.duration(record.durationSeconds))
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
}

/// The viewer only ever reads (#161).
extension JSONLHistoryStore: HistoryReading {}
