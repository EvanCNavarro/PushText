import Foundation

/// A record that could not be turned into a line. Encoding JSON that is not valid UTF-8 should be
/// impossible, but returning a silent empty string here would write a blank record instead.
public enum HistoryEncodingError: Error { case notUTF8 }

/// One dictation, as persisted (#10).
public struct HistoryRecord: Equatable, Sendable, Codable {
    public let text: String
    public let recordedAt: Date
    public let durationSeconds: TimeInterval

    public init(text: String, recordedAt: Date, durationSeconds: TimeInterval) {
        self.text = text
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
    }
}

/// JSONL encoding, kept in Core because it is pure string-to-record and needs no filesystem.
///
/// **Why JSONL and not one JSON array.** Appending is a single write of one line. An array has to
/// be read, parsed, mutated and rewritten on every utterance, so a crash mid-write loses the whole
/// history rather than the last entry. The same property covers corruption on read: a bad line
/// costs that line.
///
/// That is the ONLY reason the format was chosen, so `decodeFile` skips unparseable lines instead
/// of throwing. A decoder that gave up on the first bad line would hand back an empty history and
/// discard the very durability the format was picked for.
public extension HistoryRecord {

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Sorted so a line is reproducible and diffable; ISO-8601 so the file stays readable by a
        // human with `tail`, which is half the point of a text format.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// One record as one line. NEVER contains a newline: JSON escapes them inside the string, which
    /// is what keeps a multi-line dictation - "new paragraph" is an ordinary thing to say - from
    /// being read back as two broken records.
    static func encodeLine(_ record: HistoryRecord) throws -> String {
        guard let line = String(bytes: try encoder.encode(record), encoding: .utf8) else {
            throw HistoryEncodingError.notUTF8
        }
        return line
    }

    static func decodeLine(_ line: String) throws -> HistoryRecord {
        try decoder.decode(HistoryRecord.self, from: Data(line.utf8))
    }

    /// Every record the file still holds. Unparseable and blank lines are skipped, not fatal.
    static func decodeFile(_ contents: String) -> [HistoryRecord] {
        contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            try? decodeLine(String($0))
        }
    }

    /// Keeps the most recent `count` lines.
    ///
    /// Newest, not oldest: trimming the wrong end silently discards what the user is most likely to
    /// want back. Operates on LINES rather than decoded records so a corrupt line is carried
    /// through untouched rather than being quietly dropped by a trim.
    static func trim(_ contents: String, toMostRecent count: Int) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(max(0, count)).joined(separator: "\n")
    }
}
