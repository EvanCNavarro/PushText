import Foundation
import PushTextCore

/// Where the user's dictionary entries come from (#82).
public protocol DictionaryStore: Sendable {
    func load() -> [DictionaryEntry]
    func save(_ entries: [DictionaryEntry])
}

/// JSONL beside the history file.
///
/// **Why the dictionary needs a store at all.** #13 measured that the engine cannot be biased -
/// `AnalysisContext.contextualStrings` produced byte-identical transcripts on 3 of 3 runs - so a
/// post-pass is the ONLY mechanism available for proper nouns. #9 built that post-pass with 15
/// tests and no source of entries, which made it permanently inert.
///
/// Same format as `JSONLHistoryStore` and deliberately NOT the same code: two record types with
/// different fields behind one generic would be a contorted abstraction for a five-line encoder
/// (CLAUDE.md prefers duplication to that trade). What IS shared is the reasoning - one line per
/// entry, and a bad line costs that line.
///
/// That property matters more here than for history, because this file is EDITED BY HAND. A typo
/// is the expected failure, not an exotic one, and losing the whole dictionary to one misplaced
/// brace would be the worst possible response to it.
public struct JSONLDictionaryStore: DictionaryStore {

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/PushText/dictionary.jsonl`, beside the history.
    public static func defaultURL(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("PushText", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dictionary.jsonl")
    }

    public func load() -> [DictionaryEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return contents.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(DictionaryEntry.self, from: Data($0.utf8)) }
            // An EMPTY spoken form is worse than a useless rule: it would match everywhere.
            .filter { !$0.spoken.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func save(_ entries: [DictionaryEntry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry) else { return nil }
            return String(bytes: data, encoding: .utf8)
        }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Creates the file with one self-documenting example, if it does not exist.
    ///
    /// The example's `spoken` and `written` are IDENTICAL, so it teaches the format while rewriting
    /// nothing. An example with differing forms would silently change text the user never asked to
    /// change, and they would have to notice and delete it before the app behaved as expected.
    public func createWithExampleIfMissing() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        save([DictionaryEntry(spoken: "example phrase", written: "example phrase")])
    }
}
