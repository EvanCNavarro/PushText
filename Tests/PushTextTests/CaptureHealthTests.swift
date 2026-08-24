import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// Whether the user is told that an utterance lost audio (#71).
///
/// `AVAudioEngineCapture` has counted `restartCount`, `restartFailures` and `droppedFrames` since
/// #70, and NOTHING read any of them - including `droppedFrames`, whose own comment says it is
/// "surfaced rather than swallowed". A counter nobody reads is the same silence it was added to
/// break: the user gets a short transcript and reads it as bad recognition.
@Suite("Capture health")
@MainActor
struct CaptureHealthTests {

    private final class LossyCapture: AudioCapture, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (PushTextKit.AudioBuffer) -> Void)?
        private let reported: CaptureHealth

        init(health: CaptureHealth) { reported = health }

        var health: CaptureHealth { reported }

        func start(onBuffer: @escaping @Sendable (PushTextKit.AudioBuffer) -> Void) throws {
            lock.lock(); handler = onBuffer; lock.unlock()
        }
        func stop() { lock.lock(); handler = nil; lock.unlock() }
        func deliver() {
            lock.lock(); let h = handler; lock.unlock()
            h?(PushTextKit.AudioBuffer(samples: [0.1], sampleRate: 48_000, startTime: 0))
        }
    }

    private func settle(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("A clean capture is clean, and any loss is not")
    func cleanIsClean() {
        #expect(CaptureHealth().isClean)
        #expect(!CaptureHealth(restarts: 1).isClean)
        #expect(!CaptureHealth(restartFailures: 1).isClean)
        #expect(!CaptureHealth(droppedFrames: 1).isClean)
    }

    /// An engine that never loses anything must produce NO warning. A notice on every dictation is
    /// one the user stops reading, which costs the real ones their meaning.
    @Test("A clean utterance produces no warning")
    func cleanUtteranceIsSilent() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let model = AppModel(engine: engine, capture: capture, injector: nil)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { model.machine.state == .idle }
        #expect(model.lastCaptureWarning == nil)
    }

    /// The point of #71: a device change is no longer silent.
    @Test("A device restart during the utterance is reported to the user")
    func restartIsReported() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth(restarts: 1))
        let model = AppModel(engine: engine, capture: capture, injector: nil)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { model.lastCaptureWarning != nil }
        let warning = model.lastCaptureWarning ?? ""
        #expect(warning.lowercased().contains("device"),
                "a restart must name the CAUSE the user can act on, got: \(warning)")
    }

    /// Dropped frames are a DIFFERENT cause with a different remedy, so they must not share copy
    /// with a device change - telling someone their input device changed when it did not sends
    /// them looking for a cable.
    @Test("Dropped frames read differently from a device change")
    func droppedFramesAreTheirOwnMessage() {
        let restart = AppModel.captureWarning(for: CaptureHealth(restarts: 1))
        let dropped = AppModel.captureWarning(for: CaptureHealth(droppedFrames: 4_800))

        #expect(restart != nil && dropped != nil)
        #expect(restart != dropped)
        #expect(dropped?.lowercased().contains("device") != true)
    }

    /// A restart that FAILED lost the rest of the utterance, not a fraction of it. Saying the same
    /// thing for both understates a total loss.
    @Test("A failed restart is stated more strongly than a successful one")
    func failedRestartIsDistinct() {
        let recovered = AppModel.captureWarning(for: CaptureHealth(restarts: 1))
        let failed = AppModel.captureWarning(for: CaptureHealth(restarts: 1, restartFailures: 1))

        #expect(recovered != failed)
    }
    private final class SpyHistory: HistoryStore, @unchecked Sendable {
        private let lock = NSLock()
        private var records: [HistoryRecord] = []
        func append(_ record: HistoryRecord) { lock.lock(); records.append(record); lock.unlock() }
        func load() -> [HistoryRecord] { lock.lock(); defer { lock.unlock() }; return records }
        func clear() { lock.lock(); records = []; lock.unlock() }
    }

    /// History has to be WIRED, not merely built (#10). Three components in this repo were shipped
    /// with tests and referenced by the app zero times; this asserts the store is actually called.
    @Test("A completed dictation is written to history")
    func dictationIsRecorded() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["recorded words"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let history = SpyHistory()
        let model = AppModel(engine: engine, capture: capture, injector: nil, history: history)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !history.load().isEmpty }
        #expect(history.load().map(\.text) == ["recorded words"])
    }

    /// An empty transcript is not a dictation. Recording it fills the history with blanks the user
    /// never spoke, which makes the real entries harder to find.
    @Test("An empty transcript is not recorded")
    func emptyTranscriptIsNotRecorded() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: [""],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let history = SpyHistory()
        let model = AppModel(engine: engine, capture: capture, injector: nil, history: history)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { model.machine.state == .idle || model.machine.state == .failed(.noSpeechDetected) }
        #expect(history.load().isEmpty)
    }

    private final class SpyInjector: TextInjector, @unchecked Sendable {
        private let lock = NSLock()
        private var texts: [String] = []
        var isTrusted: Bool { true }
        func inject(_ text: String) async throws { record(text) }
        private func record(_ text: String) { lock.lock(); texts.append(text); lock.unlock() }
        var injected: [String] { lock.lock(); defer { lock.unlock() }; return texts }
    }

    private struct StubDictionary: DictionaryStore {
        let entries: [DictionaryEntry]
        func load() -> [DictionaryEntry] { entries }
        func save(_ entries: [DictionaryEntry]) {}
    }

    /// #82: the matcher has existed since #9 and was applied to nothing. This asserts the
    /// transcript actually passes through it before injection.
    @Test("The dictionary rewrites the transcript before it is injected")
    func dictionaryRewritesBeforeInjection() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["open push text now"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let dictionary = StubDictionary(entries: [DictionaryEntry(spoken: "push text",
                                                                  written: "PushText")])
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             dictionary: dictionary)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(injector.injected == ["open PushText now"])
    }

    /// An empty dictionary must be a no-op, not a mangling. This is the state every user starts in.
    @Test("An empty dictionary leaves the transcript untouched")
    func emptyDictionaryChangesNothing() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["leave me alone"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             dictionary: StubDictionary(entries: []))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(injector.injected == ["leave me alone"])
    }

    /// History records what the user actually got. Storing the pre-rewrite text would make the
    /// history disagree with the document they pasted into.
    @Test("History records the rewritten text, not the raw transcript")
    func historyRecordsWhatWasInjected() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["open push text now"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let history = SpyHistory()
        let model = AppModel(engine: engine, capture: capture, injector: SpyInjector(),
                             history: history,
                             dictionary: StubDictionary(entries: [
                                DictionaryEntry(spoken: "push text", written: "PushText")]))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !history.load().isEmpty }
        #expect(history.load().map(\.text) == ["open PushText now"])
    }

    /// Found by planting: dropping `levels.record(...)` from the capture callback left the whole
    /// suite green. The HUD waveform is driven by that feed, so a break shows up as bars that never
    /// move while recording - visible to a user, invisible to the tests.
    @Test("Captured audio reaches the level meter that drives the HUD")
    func capturedAudioReachesTheLevelMeter() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["x"],
                                                                  latency: .milliseconds(1)))
        let capture = LoudCapture()
        let model = AppModel(engine: engine, capture: capture, injector: nil)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliverLoud()

        #expect(await settle { model.currentAudioLevel > 0 },
                "level stayed at \(model.currentAudioLevel) - samples never reached the meter")
    }

    /// Delivers samples loud enough to register above the meter's -60 dBFS floor.
    private final class LoudCapture: AudioCapture, @unchecked Sendable {
        private let lock = NSLock()
        private var handler: (@Sendable (PushTextKit.AudioBuffer) -> Void)?
        func start(onBuffer: @escaping @Sendable (PushTextKit.AudioBuffer) -> Void) throws {
            lock.lock(); handler = onBuffer; lock.unlock()
        }
        func stop() { lock.lock(); handler = nil; lock.unlock() }
        func deliverLoud() {
            lock.lock(); let h = handler; lock.unlock()
            h?(PushTextKit.AudioBuffer(samples: Array(repeating: 0.6, count: 512),
                                       sampleRate: 48_000, startTime: 0))
        }
    }

    /// A stub whose rewrite is VISIBLE in the output, so "cleanup ran" and "cleanup was skipped"
    /// cannot produce the same text. A stub returning its input would pass whether or not the
    /// provider is wired, which is the whole defect #94 describes.
    private actor StubCleanup: CleanupProvider {
        private let transform: @Sendable (String) -> String
        /// A lock-guarded box rather than actor state, so `settle`'s synchronous closure can read
        /// it without hopping onto this actor.
        let calls = Calls()
        init(_ transform: @escaping @Sendable (String) -> String) { self.transform = transform }
        var isAvailable: Bool { true }
        func prewarm() async { calls.recordPrewarm() }
        func clean(_ transcript: Transcript) async throws -> String {
            calls.recordClean()
            return transform(transcript.text)
        }
    }

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var prewarms = 0
        private var cleans = 0
        func recordPrewarm() { lock.lock(); prewarms += 1; lock.unlock() }
        func recordClean() { lock.lock(); cleans += 1; lock.unlock() }
        var prewarmCount: Int { lock.lock(); defer { lock.unlock() }; return prewarms }
        var cleanCount: Int { lock.lock(); defer { lock.unlock() }; return cleans }
    }

    /// Prewarm has to happen at KEY-DOWN. Warming when the transcript arrives would be warming at
    /// exactly the moment the user is already waiting, which is the cost it exists to remove - and
    /// a test that only checked "prewarm was called eventually" would pass on that broken version.
    @Test("Cleanup is prewarmed when speech starts, before any transcript exists")
    func cleanupIsPrewarmedAtKeyDown() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello there"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let cleanup = StubCleanup { $0 }
        let model = AppModel(engine: engine, capture: capture, injector: SpyInjector(),
                             cleanup: cleanup)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }

        #expect(await settle { cleanup.calls.prewarmCount > 0 },
                "no prewarm by the time recording started")
        #expect(cleanup.calls.cleanCount == 0,
                "prewarmed only - nothing has been transcribed yet")
    }

    @Test("Cleanup runs and its result is what gets injected")
    func cleanupResultReachesTheInjector() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello there"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             cleanup: StubCleanup { $0 + " [cleaned]" },
                             settingsStore: FakeSettings(settings: AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode)))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(injector.injected == ["hello there [cleaned]"])
    }

    /// ORDERING. The dictionary is the user's explicit configuration; the model is a guess. If
    /// cleanup ran last it could undo a rewrite the user asked for by name, and nothing would say
    /// so. This stub undoes it deliberately.
    @Test("The user's dictionary wins over cleanup")
    func dictionaryIsAppliedAfterCleanup() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["open push text now"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             dictionary: StubDictionary(entries: [
                                DictionaryEntry(spoken: "push text", written: "PushText")]),
                             cleanup: StubCleanup { $0.replacingOccurrences(of: "PushText",
                                                                           with: "push text") },
                             settingsStore: FakeSettings(settings: AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode)))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(injector.injected == ["open PushText now"],
                "cleanup undid the dictionary - it must run BEFORE the user's rules, not after")
    }

    /// The invariant `historyRecordsWhatWasInjected` states but cannot see: it compares history to
    /// the dictionary result, which stays equal to the injected text even when cleanup is skipped.
    /// Comparing history to what the INJECTOR actually received is what makes it load-bearing.
    @Test("History matches the injected text when cleanup rewrites it")
    func historyMatchesInjectedTextUnderCleanup() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello there"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let history = SpyHistory()
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             history: history,
                             cleanup: StubCleanup { $0 + " [cleaned]" },
                             settingsStore: FakeSettings(settings: AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode)))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty && !history.load().isEmpty }
        #expect(history.load().map(\.text) == injector.injected,
                "history must record what the user actually got")
    }

    /// An in-memory `SettingsStore`, so a test never touches real user defaults.
    struct FakeSettings: SettingsStore {
        let settings: AppSettings
        func load() -> AppSettings { settings }
        func save(_ settings: AppSettings) {}
        func purge() {}
    }

    /// #103. The assertion is that `clean` is NEVER CALLED - not that the text came back unchanged.
    /// Cleanup frequently returns its input unchanged anyway, so a text assertion would pass on a
    /// gate that does nothing, which is the whole failure being guarded against.
    @Test("Cleanup does not run when the setting is off")
    func cleanupSkippedWhenDisabled() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello there"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let cleanup = StubCleanup { $0 + " [cleaned]" }
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             cleanup: cleanup,
                             settingsStore: FakeSettings(settings: AppSettings(cleanupEnabled: false, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode)))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(cleanup.calls.cleanCount == 0, "the model was asked to clean while the setting was off")
        #expect(injector.injected == ["hello there"])
    }

    /// The other half: with the setting ON the provider must actually be consulted, or the gate has
    /// simply disabled the feature permanently.
    @Test("Cleanup runs when the setting is on")
    func cleanupRunsWhenEnabled() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["hello there"],
                                                                  latency: .milliseconds(1)))
        let capture = LossyCapture(health: CaptureHealth())
        let injector = SpyInjector()
        let cleanup = StubCleanup { $0 + " [cleaned]" }
        let model = AppModel(engine: engine, capture: capture, injector: injector,
                             cleanup: cleanup,
                             settingsStore: FakeSettings(settings: AppSettings(cleanupEnabled: true, hotkeyKeyCode: HotkeyBinding.rightOption.keyCode)))

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        capture.deliver()
        model.handle(.released, at: 1)

        _ = await settle { !injector.injected.isEmpty }
        #expect(cleanup.calls.cleanCount == 1)
        #expect(injector.injected == ["hello there [cleaned]"])
    }

    /// A cleanup stub that blocks until released, so a test can hold the machine in `.cleaning` and
    /// cancel it MID-FLIGHT. Cancellation is a property that only exists during the operation - a
    /// test that inspects the end state after cleanup finished cannot see it at all.
    private actor GatedCleanup: CleanupProvider {
        private var release: CheckedContinuation<Void, Never>?
        private var released = false
        let calls = Calls()
        var isAvailable: Bool { true }
        func clean(_ transcript: Transcript) async throws -> String {
            calls.recordClean()
            if !released {
                await withCheckedContinuation { self.release = $0 }
            }
            return transcript.text + " [cleaned]"
        }
        func open() { released = true; release?.resume(); release = nil }
    }

    private func enabledSettings() -> FakeSettings {
        FakeSettings(settings: AppSettings(cleanupEnabled: true,
                                           hotkeyKeyCode: HotkeyBinding.rightOption.keyCode))
    }

    @Test("Cancelling while transcribing injects nothing")
    func cancelDuringTranscribing() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["unwanted words"],
                                                                  latency: .seconds(3)))
        let injector = SpyInjector()
        let model = AppModel(engine: engine, capture: LossyCapture(health: CaptureHealth()),
                             injector: injector)

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .transcribing }

        model.apply(.cancelRequested)
        #expect(model.machine.state == .idle, "cancel was refused while transcribing")
        _ = await settle { false }
        #expect(injector.injected.isEmpty, "cancelled text was injected anyway")
    }

    /// The one the issue did not anticipate: history is written INSIDE the cleaning stage, so a
    /// cancel there could record a transcript that was never typed - breaking the invariant #97
    /// established, that history equals what the user actually got.
    @Test("Cancelling while cleaning records nothing in history")
    func cancelDuringCleaningLeavesNoHistory() async {
        let engine = MockTranscriptionEngine(configuration: .init(phrases: ["unwanted words"],
                                                                  latency: .milliseconds(1)))
        let injector = SpyInjector()
        let history = SpyHistory()
        let cleanup = GatedCleanup()
        let model = AppModel(engine: engine, capture: LossyCapture(health: CaptureHealth()),
                             injector: injector, history: history, cleanup: cleanup,
                             settingsStore: enabledSettings())

        model.handle(.pressed, at: 0)
        _ = await settle { model.machine.state == .recording }
        model.handle(.released, at: 1)
        _ = await settle { model.machine.state == .cleaning }

        model.apply(.cancelRequested)
        #expect(model.machine.state == .idle, "cancel was refused while cleaning")
        await cleanup.open()
        _ = await settle { false }

        #expect(injector.injected.isEmpty, "cancelled text was injected")
        #expect(history.load().isEmpty, "cancelled text was written to history")
    }

    /// The discriminator. `.injecting` is too late - the paste is in flight - so cancel must NOT be
    /// accepted there. A change that simply allowed cancel everywhere would pass both tests above.
    @Test("Cancelling while injecting is refused")
    func cancelDuringInjectingIsRefused() async {
        let machine = DictationMachine(state: .injecting)
        var copy = machine
        copy.apply(.cancelRequested)
        #expect(copy.state == .injecting, "cancel was accepted after the paste started")
    }

}
