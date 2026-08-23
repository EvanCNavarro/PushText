import Foundation

/// One rewrite: what the recognizer tends to hear, and what should actually be typed.
public struct DictionaryEntry: Equatable, Sendable, Codable {
    /// The spoken form, as prose. Matched case-insensitively and across separator variants.
    public let spoken: String
    /// The exact text to type. Written verbatim, never interpreted.
    public let written: String

    public init(spoken: String, written: String) {
        self.spoken = spoken
        self.written = written
    }
}

/// Rewrites recognized text into the user's own vocabulary (#9).
///
/// **A post-pass, not engine biasing.** `AnalysisContext.contextualStrings` is the obvious mechanism
/// and `docs/research/01` sec 1.6 says to treat it as "UNVERIFIED and probably absent" on
/// `SpeechTranscriber`: a forum responder reports it works only with `DictationTranscriber`, and
/// Argmax independently reports SpeechAnalyzer "lacks the Custom Vocabulary feature". #13 spikes
/// that; this works either way, and if biasing turns out to exist the two compose.
///
/// Pure, so every rule here is testable without a recognizer.
public struct CustomDictionary: Sendable {

    private struct Rule {
        let regex: NSRegularExpression
        let written: String
    }

    private let rules: [Rule]

    public init(entries: [DictionaryEntry]) {
        // LONGEST FIRST. A short entry otherwise consumes the front of a longer one and the longer
        // entry can never match: "cloud code" would eat the start of "cloud code studio" forever.
        rules = entries
            .filter { !$0.spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.spoken.count > $1.spoken.count }
            .compactMap { entry in
                guard let regex = Self.pattern(for: entry.spoken) else { return nil }
                return Rule(regex: regex, written: entry.written)
            }
    }

    public func apply(to text: String) -> String {
        guard !rules.isEmpty else { return text }

        // NFC up front so a composed "é" and a decomposed "e" + combining acute compare equal.
        // Dictation output and a hand-typed dictionary do not agree on which form to use.
        var result = text.precomposedStringWithCanonicalMapping

        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            // The replacement is DATA, not a template: a written form containing "$1" must be typed,
            // not read as a capture-group reference.
            let escaped = NSRegularExpression.escapedTemplate(for: rule.written)
            result = rule.regex.stringByReplacingMatches(in: result,
                                                         options: [],
                                                         range: range,
                                                         withTemplate: escaped)
        }
        return result
    }

    /// Builds the match pattern for one spoken form.
    ///
    /// Two deliberate choices:
    ///
    /// **Parts are joined with `[\s\-]*`**, so "cloud code" matches spaced, hyphenated, or run
    /// together - a recognizer produces all three for the same phrase.
    ///
    /// **The fence is a letter/number lookaround, not `\b`.** It says exactly what is meant: not
    /// immediately preceded or followed by another letter or digit. That is what stops "api"
    /// rewriting the middle of "apiary" and turning the user's prose into product names.
    ///
    /// An earlier version of this comment claimed `\b` "misses (pushtext)". MEASURED: it does not -
    /// swapping in `\b` leaves every punctuation case passing, because ICU's `\b` is Unicode-aware.
    /// The one real difference is UNDERSCORE, which `\b` treats as a word character: `\b` refuses to
    /// rewrite inside `foo_api_bar` and these lookarounds accept it. Neither is obviously right, so
    /// the behaviour is pinned by a test rather than left to whichever fence someone reaches for.
    private static func pattern(for spoken: String) -> NSRegularExpression? {
        let normalised = spoken.precomposedStringWithCanonicalMapping
        let parts = normalised
            .components(separatedBy: CharacterSet(charactersIn: " -"))
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        // Each part escaped: a user's dictionary is data, so "C++" is literal rather than a syntax
        // error, and ".*" matches a full stop and a star.
        let body = parts.map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "[\\s\\-]*")
        let fenced = "(?<![\\p{L}\\p{N}])" + body + "(?![\\p{L}\\p{N}])"

        return try? NSRegularExpression(pattern: fenced, options: [.caseInsensitive])
    }
}
