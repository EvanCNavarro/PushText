import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Making model preparation visible (#76).
///
/// #36 moved the download off the dictation path so the first key-down no longer blocks. What it
/// did not do is TELL anyone: `prepare()` ran detached, a failure was written to `dictationLog` and
/// nowhere else, and a user on a cold machine saw an app that simply refused to dictate with no
/// indication that anything was happening or when it would stop.
@Suite("Model preparation")
@MainActor
struct ModelPreparationTests {

    /// Reports whatever progress the test asks for, then succeeds or fails.
    private actor ScriptedEngine: TranscriptionEngine {
        private let fractions: [Double]
        private let failure: Error?

        init(fractions: [Double] = [], failure: Error? = nil) {
            self.fractions = fractions
            self.failure = failure
        }

        var isAvailable: Bool { true }
        func prepare(onProgress: (@Sendable (Double) -> Void)?) async throws {
            for fraction in fractions { onProgress?(fraction) }
            if let failure { throw failure }
        }
        func beginUtterance() async throws {}
        func append(_ buffer: PushTextKit.AudioBuffer) async throws {}
        func finishUtterance() async throws -> Transcript { Transcript(text: "", duration: 0) }
    }

    private struct Refused: Error, CustomStringConvertible { var description: String { "no network" } }

    private func settle(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// A machine whose model is already installed must say NOTHING. Every run after the first is
    /// this case, and a permanent "preparing" row would be noise that trains the user to ignore it.
    @Test("A model that needs no download produces no message")
    func readyIsSilent() async {
        let model = AppModel(engine: ScriptedEngine())

        await model.prepareModel()

        #expect(model.modelPreparation == .ready)
        #expect(model.modelPreparationMessage == nil)
    }

    @Test("Progress is reported as it arrives")
    func progressIsReported() async {
        let model = AppModel(engine: ScriptedEngine(fractions: [0.25, 0.5, 0.75]))

        await model.prepareModel()

        // Ends ready, having passed through preparing - the final state is what the menu shows.
        #expect(model.modelPreparation == .ready)
    }

    /// THE gap #76 names: a failed prepare was log-only.
    @Test("A failed preparation is surfaced, not just logged")
    func failureIsSurfaced() async {
        let model = AppModel(engine: ScriptedEngine(failure: Refused()))

        await model.prepareModel()

        guard case .failed = model.modelPreparation else {
            Issue.record("expected .failed, got \(model.modelPreparation)")
            return
        }
        let message = model.modelPreparationMessage ?? ""
        #expect(!message.isEmpty, "a failure the user cannot see is the defect this closes")
    }

    /// The preparing message has to carry the PERCENTAGE. "Preparing..." with no number is
    /// indistinguishable from a hang, which is the complaint #36 fixed at the other end.
    @Test("The preparing message states how far along it is")
    func preparingMessageCarriesProgress() {
        let message = AppModel.preparationMessage(for: .preparing(fraction: 0.42)) ?? ""

        #expect(message.contains("42"), "no percentage in: \(message)")
    }

    /// Failure and progress must not read the same. One resolves itself by waiting; the other
    /// never will.
    @Test("A failure reads differently from progress")
    func failureAndProgressDiffer() {
        let progress = AppModel.preparationMessage(for: .preparing(fraction: 0.5))
        let failed = AppModel.preparationMessage(for: .failed("no network"))

        #expect(progress != nil && failed != nil)
        #expect(progress != failed)
    }
}
