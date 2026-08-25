import Foundation

/// Fuzzy search across a dictation transcript, and the ranges to highlight (#167).
///
/// **Word-level, not character-level.** The obvious fuzzy algorithm is a subsequence match, the way
/// a file finder works - and it is wrong for prose. "btf" would match "Book a table for four", every
/// long transcript would match nearly every short query, and the highlight would be scattered single
/// characters across a sentence rather than anything a person can read. Users are looking for WORDS
/// they said.
///
/// **AND across the query's words.** Typing a second word has to narrow the list. A search that
/// widens as you type cannot be used to find anything.
public enum TranscriptSearch {

    /// Where a query matched, in the transcript's own indices.
    public struct Match: Equatable, Sendable {
        /// Ordered, non-overlapping, and covering only the matched words.
        public let ranges: [Range<String.Index>]
    }

    /// `nil` when the query is empty or the transcript does not match.
    public static func match(query: String, in text: String) -> Match? {
        let tokens = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !tokens.isEmpty else { return nil }

        let transcriptWords = words(in: text)
        var hits: [Range<String.Index>] = []
        for token in tokens {
            let hit = transcriptWords.filter { matches(token: token, word: $0.folded) }
            // Every token must land somewhere, or the transcript is not a result at all.
            guard !hit.isEmpty else { return nil }
            hits.append(contentsOf: hit.map(\.range))
        }
        return Match(ranges: merged(hits))
    }

    // MARK: - Matching one word

    /// Below this length, edit distance stops discriminating: at three characters "car" is one edit
    /// from "cat", "cot", "can" and "bar". Fuzzing them turns the search into noise, so short tokens
    /// are substring-only.
    private static let shortestFuzzableToken = 4

    private static func matches(token: String, word: String) -> Bool {
        if word.contains(token) { return true }
        guard token.count >= shortestFuzzableToken else { return false }
        let budget = token.count >= 7 ? 2 : 1
        // A length gap wider than the budget cannot be closed, and checking it first skips almost
        // every comparison in a long transcript.
        guard abs(word.count - token.count) <= budget else { return false }
        return editDistance(Array(word), Array(token), within: budget) <= budget
    }

    /// Levenshtein, two rows, abandoned as soon as every cell exceeds the budget.
    private static func editDistance(_ lhs: [Character], _ rhs: [Character], within budget: Int) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for row in 1...lhs.count {
            current[0] = row
            var best = current[0]
            for column in 1...rhs.count {
                let substitution = previous[column - 1]
                    + (lhs[row - 1] == rhs[column - 1] ? 0 : 1)
                current[column] = min(previous[column] + 1, current[column - 1] + 1, substitution)
                best = min(best, current[column])
            }
            if best > budget { return budget + 1 }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    // MARK: - Splitting the transcript

    private struct Word {
        let range: Range<String.Index>
        let folded: String
    }

    /// Words as a reader sees them, so "invoice," matches `invoice` and the highlight still covers
    /// the word rather than the comma. An apostrophe is part of a word - "don't" is one.
    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        for index in text.indices {
            let character = text[index]
            let isWord = character.isLetter || character.isNumber || character == "'"
                || character == "\u{2019}"
            if isWord, start == nil { start = index }
            if !isWord, let from = start {
                words.append(Word(range: from..<index, folded: fold(String(text[from..<index]))))
                start = nil
            }
        }
        if let from = start {
            words.append(Word(range: from..<text.endIndex, folded: fold(String(text[from...]))))
        }
        return words
    }

    /// Case and accents both folded: someone searching for what they SAID types "cafe", and the
    /// transcript may well say "Café".
    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Sorted and coalesced. The same word can be hit by more than one token, and painting a
    /// background twice over the same characters is how a highlight ends up looking wrong.
    private static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
