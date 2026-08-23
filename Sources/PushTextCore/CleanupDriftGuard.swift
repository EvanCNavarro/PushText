import Foundation

/// Why a cleanup candidate was refused.
///
/// A REASON rather than a boolean, because #14 will run this in shadow mode - apply the raw text,
/// log the rejection - to calibrate the thresholds against real dictation. A boolean makes that
/// calibration impossible: "rejected 8% of utterances" is useless without knowing whether they were
/// inversions or length trips.
public enum CleanupRejection: Equatable, Sendable {
    case empty
    /// The negation count changed, so the text may mean the opposite of what was said.
    case meaningInverted
    case tooShort(ratio: Double)
    case tooLong(ratio: Double)
    case tooDifferent(similarity: Double)
    /// A content word appeared that was not in the transcript.
    case ungroundedContent(token: String)
}

public enum CleanupVerdict: Equatable, Sendable {
    case plausible
    case rejected(CleanupRejection)
}

/// Decides whether a "cleaned" transcript is a plausible cleanup of what was said, or drift.
///
/// **This is the differentiator, not a nicety.** `docs/research/06` sec 4.4 read the
/// response-consuming path in six projects. Handy (30k stars), VoiceInk (6k), Whispering (4.7k),
/// PipeVoice and mlxwhisperinput all fall back to the raw transcript ONLY on transport errors - blank
/// input, API failure, empty response - and never compare content. Zero occurrences of Levenshtein,
/// edit distance, similarity, word overlap or length ratio in any of them. In the research's words:
/// "If the model answers the question, VoiceInk types the answer."
///
/// **Thresholds are a starting point, not received truth.** They are read off
/// `EtanHey/voicelayer`'s `validatePolishCandidate()`, the only real implementation found - and the
/// research is explicit that it is a 1-star repo: an existence proof and a well-considered design,
/// not a battle-tested standard.
///
/// Pure, so every threshold is testable without a model, a network, or a machine.
public enum CleanupDriftGuard {

    /// Below these an utterance is too short for length ratios to mean anything: "um yeah ok" ->
    /// "Yeah, okay." is a 30% swing on three words, and bounding it would reject most real short
    /// dictations.
    static let lengthCheckMinimumCharacters = 80
    static let lengthCheckMinimumWords = 12

    static let minimumLengthRatio = 0.72   // the truncation failure Ma et al. measured
    static let maximumLengthRatio = 1.35
    static let minimumSimilarityLong = 0.62
    /// Unused: see the deviation note in `verdict(raw:cleaned:)`. Kept so the researched value is
    /// visible to whoever calibrates these against real dictation in #14's shadow mode.
    static let minimumSimilarityShort = 0.72

    /// Catches meaning inversion, which is the worst failure available and almost free to detect.
    static let negations: Set<String> = [
        "no", "not", "never", "without", "cannot", "cant", "dont", "doesnt", "didnt",
        "wont", "shouldnt", "wouldnt", "couldnt", "isnt", "arent", "wasnt", "werent", "nor", "none"
    ]

    /// Words cleanup is EXPECTED to add or drop. Grounding must ignore them or every legitimate
    /// cleanup is rejected and the guard is worse than useless.
    static let functionWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "is", "it", "its",
        "of", "on", "or", "so", "that", "the", "then", "there", "this", "to", "was", "were", "with",
        "we", "i", "you", "he", "she", "they", "am", "are", "be", "been", "being", "do", "does",
        "did", "have", "has", "had", "will", "would", "can", "could", "should", "just", "well",
        "um", "uh", "like", "know", "okay", "ok", "yeah"
    ]

    public static func verdict(raw: String, cleaned: String) -> CleanupVerdict {
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Nothing was said, so nothing can drift. The caller has already decided this is not an
        // utterance; turning it into a rejection would surface a failure the user did not cause.
        if rawTrimmed.isEmpty { return .plausible }
        guard !cleanTrimmed.isEmpty else { return .rejected(.empty) }

        let rawTokens = tokens(rawTrimmed)
        let cleanTokens = tokens(cleanTrimmed)

        // 1. Meaning inversion first: it is the cheapest check and the most damaging failure.
        if count(of: negations, in: rawTokens) != count(of: negations, in: cleanTokens) {
            return .rejected(.meaningInverted)
        }

        // 2. Length, only where a ratio is meaningful.
        let longEnough = rawTrimmed.count >= lengthCheckMinimumCharacters
            || rawTokens.count >= lengthCheckMinimumWords
        if longEnough {
            let ratio = Double(cleanTrimmed.count) / Double(rawTrimmed.count)
            if ratio < minimumLengthRatio { return .rejected(.tooShort(ratio: ratio)) }
            if ratio > maximumLengthRatio { return .rejected(.tooLong(ratio: ratio)) }
        }

        // 3. Grounding: every content word in the output must be available in the input. This is the
        // Apple paper's hallucination metric as a runtime guard, and it is what catches an answer
        // to a dictated question - "Paris" is not in "what is the capital of France".
        var available = multiset(of: rawTokens)
        for token in cleanTokens where !functionWords.contains(token) {
            guard let remaining = available[token], remaining > 0 else {
                return .rejected(.ungroundedContent(token: token))
            }
            available[token] = remaining - 1
        }

        // 4. Similarity last: most expensive, least specific, and only for inputs long enough for
        // character-level edit distance to mean anything.
        //
        // DELIBERATE DEVIATION from the researched thresholds, which give 0.72 for short inputs.
        // Measured here: "um yeah ok" -> "Yeah, okay." scores 0.36, because on a ten-character
        // string the punctuation and casing ARE the edit distance. Applying a floor there would
        // reject the most ordinary short cleanup there is, so short utterances would never be
        // cleaned at all. Grounding is the effective guard at that length - it already catches
        // "call mom" -> "Paris" - and negation catches "yes" -> "no", so dropping this check for
        // short inputs loses no real coverage. Recorded rather than silently retuned, because the
        // number came from `voicelayer` and the next reader deserves to know it was changed.
        if longEnough {
            let similarity = normalisedSimilarity(rawTrimmed.lowercased(), cleanTrimmed.lowercased())
            if similarity < minimumSimilarityLong {
                return .rejected(.tooDifferent(similarity: similarity))
            }
        }

        return .plausible
    }

    // MARK: - Helpers

    /// Lowercased words, with apostrophes REMOVED before splitting rather than treated as
    /// separators.
    ///
    /// Splitting on them turned "don't" into "don" + "t", neither of which is in the negation set -
    /// so the inversion check, the single most valuable thing this guard does, was blind to every
    /// contraction. People dictate "don't", not "do not". Both the typewriter and typographic
    /// apostrophes are stripped, because dictation output and cleaned output do not agree on which
    /// one to use.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func count(of set: Set<String>, in tokens: [String]) -> Int {
        tokens.reduce(0) { $0 + (set.contains($1) ? 1 : 0) }
    }

    private static func multiset(of tokens: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for token in tokens { counts[token, default: 0] += 1 }
        return counts
    }

    /// 1 - (edit distance / longer length), so 1.0 is identical and 0.0 shares nothing.
    static func normalisedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let longer = max(lhs.count, rhs.count)
        guard longer > 0 else { return 1 }
        return 1 - (Double(levenshtein(Array(lhs), Array(rhs))) / Double(longer))
    }

    /// Two-row Levenshtein: the full matrix is unnecessary and a dictated paragraph would allocate
    /// a large one for no benefit.
    static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for row in 1...lhs.count {
            current[0] = row
            for column in 1...rhs.count {
                let substitution = previous[column - 1] + (lhs[row - 1] == rhs[column - 1] ? 0 : 1)
                current[column] = min(previous[column] + 1, current[column - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
