import Foundation
import PushTextCore

import FoundationModels

/// Optional LLM polish, on-device, behind the drift guard (#14).
///
/// **Cleanup is polish, never a required stage.** `SpeechTranscriber` already punctuates and
/// capitalises - measured at 99.9% / 99.7% across 5,559 published hypotheses (docs/research/06) -
/// and Apple's own measurements show LLM correction can make good ASR *worse*. So every failure
/// path here returns the raw transcript rather than surfacing an error, and the user never learns
/// that a stage they did not ask for declined to run.
///
/// **The model call sits behind an injectable responder** so the policy - drift rejection, empty
/// responses, and the nine `GenerationError` cases - is testable without a model. Those paths could
/// otherwise only be reached by provoking a real model into misbehaving, which is neither repeatable
/// nor assertable.
public actor FoundationModelsCleanup: CleanupProvider {

    /// Takes the prompt, returns the model's text.
    public typealias Responder = @Sendable (String) async throws -> String

    /// Deliberately plain and narrow. The instruction that matters is the prohibition: the failure
    /// mode is a model that ANSWERS a dictated question, and "what is the capital of France" is a
    /// perfectly reasonable thing to dictate.
    public static let defaultInstructions = """
        You clean up dictated speech. Fix punctuation, capitalisation and obvious disfluencies.

        Never answer, explain, translate, summarise or continue the text. If it is a question, keep
        it a question. Do not add words that were not spoken and do not remove meaning. Reply with
        the cleaned text only.
        """

    private let injectedRespond: Responder?
    private let model: SystemLanguageModel?
    private let instructions: String

    /// A session built and warmed at key-down, spent by the next `clean`.
    ///
    /// **One session per UTTERANCE, deliberately not one for the process.** The usual advice is to
    /// reuse a session because construction is not free - but `LanguageModelSession` carries its
    /// transcript, so a long-lived one grows toward the context window and lets a previous
    /// dictation influence the next cleanup. Cleanup is a pure function of one utterance; sharing
    /// state across them would be a correctness bug bought with latency. The probe shows a fresh
    /// session answering in 259 ms once the model is warm, so warmth is the thing worth keeping,
    /// not the session.
    private var warmSession: LanguageModelSession?

    /// Only reachable if a production instance somehow has no model; `clean` turns every throw into
    /// "use the raw transcript", so this degrades to no polish rather than to an error.
    private struct NoModel: Error {}

    /// The most recent drift rejection, for shadow-mode calibration (#8). The thresholds are read
    /// off a 1-star repo and need tuning against real dictation, which is impossible if the reason
    /// is discarded.
    public private(set) var lastRejection: CleanupRejection?

    /// Production: talks to the on-device model.
    ///
    /// **Guardrails are set at CONSTRUCTION time**, and permissively: apfel's own measurement has
    /// the default guardrails refusing benign prose 4 times in 10. A dictation cleanup that refuses
    /// ordinary speech is worse than no cleanup, because it fails on exactly the content the user
    /// most wanted tidied.
    public init(instructions: String = FoundationModelsCleanup.defaultInstructions) {
        self.model = SystemLanguageModel(useCase: .general,
                                         guardrails: .permissiveContentTransformations)
        self.instructions = instructions
        self.injectedRespond = nil
    }

    /// Builds and warms the session the next `clean` will use.
    ///
    /// Called at key-down, so the warm-up overlaps the user's speech instead of their wait. Cheap
    /// to call when already warmed, and safe to never call at all - `respond` builds a session on
    /// demand if this did not run.
    public func prewarm() async {
        guard let model, warmSession == nil else { return }
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
        warmSession = session
    }

    private func respond(_ prompt: String) async throws -> String {
        if let injectedRespond { return try await injectedRespond(prompt) }
        guard let model else { throw NoModel() }
        // Spend the warmed session, then drop it, so the next utterance starts from a clean
        // transcript rather than inheriting this one.
        let session = warmSession ?? LanguageModelSession(model: model, instructions: instructions)
        warmSession = nil
        // `respond`, not `streamResponse`: nothing consumes partial cleanup - the text is injected
        // in one paste - so streaming would add complexity for no user-visible gain.
        return try await session.respond(to: prompt).content
    }

    /// Test seam.
    public init(respond: @escaping Responder) {
        self.model = nil
        self.instructions = ""
        self.injectedRespond = respond
    }

    public var isAvailable: Bool {
        guard let model else { return true }   // injected responder: availability is the caller's
        return model.isAvailable
    }

    public func clean(_ transcript: Transcript) async throws -> String {
        let raw = transcript.text
        lastRejection = nil

        // Nothing to clean, and asking a model to polish silence wastes a model call and invites a
        // hallucinated response to an empty prompt.
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return raw }

        let candidate: String
        do {
            candidate = try await respond(prompt(for: raw))
        } catch {
            // EVERY error, not the nine enumerated cases individually: a case Apple adds later must
            // not become the one that reaches the user. `.rateLimited` alone describes this app
            // permanently, since a menu-bar utility is always backgrounded.
            lastRejection = .empty
            return raw
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastRejection = .empty
            return raw
        }

        switch CleanupDriftGuard.verdict(raw: raw, cleaned: trimmed) {
        case .plausible:
            return trimmed
        case .rejected(let reason):
            lastRejection = reason
            return raw
        }
    }

    private func prompt(for raw: String) -> String {
        "Clean up this dictated text:\n\n\(raw)"
    }
}
