import Foundation
import AVFoundation
import Speech
import PushTextCore

/// `TranscriptionEngine` backed by Apple's on-device `SpeechAnalyzer` (macOS 26+).
///
/// **Streaming, not chunked files.** `start(inputSequence:)` was the open question - FB22149971
/// reports it failing with `_GenericObjCError ... nilError` on macOS 26.3 while batch transcription
/// succeeds on identical audio. Measured on macOS 26.6.2 during the #11 spike it does not
/// reproduce: 10 of 10 streaming runs succeeded across 512-8192 frame buffers, matching the batch
/// arm's text exactly (docs/verification/task11-streaming-spike.md). This engine therefore feeds the
/// streaming path directly, which is what lets a partial transcript exist at all.
///
/// **Every buffer is converted before it is handed over.** A format mismatch is not an error here,
/// it is a `SIGTRAP` inside Speech.framework that no `catch` can intercept (#32, TRAP-20). See
/// `AudioFormatConverter`.
///
/// **Timestamps are monotonic by construction**, derived from a running frame count in the
/// analyzer's own sample rate - never from a host clock. Non-monotonic `bufferStartTime` is one of
/// the three causes FB22149971 is suspected to have.
public actor AppleSpeechEngine: TranscriptionEngine {

    public enum EngineError: Error, Equatable {
        /// `SpeechTranscriber.isAvailable` is false - a hardware signal (Neural Engine core count),
        /// not a missing download and not an Apple Intelligence toggle.
        case unavailable
        case localeUnsupported(String)
        /// The on-device model is not installed and installation failed or was refused.
        case modelUnavailable(String)
        /// The model is absent and this is the DICTATION path, which must not download (#36).
        ///
        /// Failing here in milliseconds is the point. `beginUtterance` used to await
        /// `downloadAndInstall()`, so on a cold machine the first key-down vanished into a
        /// multi-minute wait with the user already talking. Installation belongs in `prepare()`.
        case modelNotReady
        case notStarted
        /// The results stream did not terminate within the ceiling. Bounded deliberately: the
        /// stream is known to hang in the field, and an unbounded await would hang the app.
        case timedOut(seconds: Double)
    }

    private let requestedLocale: Locale
    private let preset: SpeechTranscriber.Preset

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<String, Error>?
    private var converter: AudioFormatConverter?

    private var startedAt: ContinuousClock.Instant?
    /// Frames handed to the analyzer, in the ANALYZER's sample rate. Sole source of
    /// `bufferStartTime`, so timestamps cannot go backwards.
    private var deliveredFrames: Int64 = 0
    private var targetSampleRate: Double = 0

    /// `isModelInstalled` is injectable for ONE reason: #36's claim is that `beginUtterance` no
    /// longer downloads, and that is a property of the NOT-installed case - which cannot occur on a
    /// machine whose model is present and which `AssetInventory` offers no way to undo. Without a
    /// seam the central assertion would be untestable and could only be re-read, not run.
    public init(
        locale: Locale = Locale(identifier: "en-US"),
        preset: SpeechTranscriber.Preset = .progressiveTranscription,
        isModelInstalled: (@Sendable (SpeechTranscriber) async -> Bool)? = nil,
        isTranscriberAvailable: (@Sendable () -> Bool)? = nil
    ) {
        self.requestedLocale = locale
        self.preset = preset
        self.isModelInstalledOverride = isModelInstalled
        self.isTranscriberAvailableOverride = isTranscriberAvailable
    }

    private let isModelInstalledOverride: (@Sendable (SpeechTranscriber) async -> Bool)?

    /// Injectable for the same reason as `isModelInstalled`, and CI proved the need: GitHub's
    /// macos-26 runner has no Neural Engine, so `SpeechTranscriber.isAvailable` is false there and
    /// `beginUtterance` throws `.unavailable` before any model check. A test that assumed capable
    /// hardware passed locally and failed in CI.
    private let isTranscriberAvailableOverride: (@Sendable () -> Bool)?

    private var transcriberIsAvailable: Bool {
        isTranscriberAvailableOverride?() ?? SpeechTranscriber.isAvailable
    }

    private func isModelInstalled(_ transcriber: SpeechTranscriber) async -> Bool {
        if let isModelInstalledOverride { return await isModelInstalledOverride(transcriber) }
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    /// Whether the recognizer can run on this hardware at all.
    ///
    /// Deliberately does NOT report model-installation state: `isAvailable` is a cheap predicate the
    /// UI polls, and asset installation is a side-effecting download that belongs in
    /// `beginUtterance`. Reporting "unavailable" for a model that merely needs downloading would
    /// make a first run look like unsupported hardware.
    public var isAvailable: Bool {
        get async { SpeechTranscriber.isAvailable }
    }

    /// Seconds of audio delivered to the analyzer this utterance. Lets a caller (or a probe) prove
    /// the audio path is live rather than merely present.
    public var deliveredSeconds: Double {
        targetSampleRate > 0 ? Double(deliveredFrames) / targetSampleRate : 0
    }

    public func beginUtterance() async throws {
        // Hardware first, deliberately: an unusable Neural Engine is permanent, and telling that
        // user "Preparing model..." would promise a wait that never ends.
        guard transcriberIsAvailable else { throw EngineError.unavailable }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw EngineError.localeUnsupported(requestedLocale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: preset)

        // Refuse rather than download (#36). `prepare()` owns installation; if it has not finished,
        // the honest answer is "not yet" in milliseconds, not a silent multi-minute await with the
        // user already speaking.
        guard await isModelInstalled(transcriber) else { throw EngineError.modelNotReady }

        // The Bool is not a success signal - it came back false while the reservation had in fact
        // taken effect (TRAP-22). Read the post-condition instead of branching on the return.
        _ = try? await AssetInventory.reserve(locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError.modelUnavailable("no compatible audio format")
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Collect BEFORE starting, so no early result can be dropped on the floor.
        resultsTask = Task { try await Self.collect(from: transcriber) }

        try await analyzer.start(inputSequence: stream)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.continuation = continuation
        self.converter = AudioFormatConverter(target: format)
        self.targetSampleRate = format.sampleRate
        self.deliveredFrames = 0
        self.startedAt = ContinuousClock.now
    }

    /// Installs the on-device model if it is missing. Called at launch, off the dictation path.
    ///
    /// Idempotent: `ensureModelInstalled` returns immediately when the status is already
    /// `.installed`, which is every run after the first on a given machine.
    ///
    /// The COLD path is not verifiable here. macOS 26's `AssetInventory` exposes `reserve` /
    /// `release` / `status` / `assetInstallationRequest` and no uninstall - read from the SDK
    /// interface - so a machine whose model is present cannot be returned to the state this method
    /// exists for. What IS verified is that it is idempotent and that `beginUtterance` no longer
    /// downloads.
    public func prepare() async throws {
        guard transcriberIsAvailable else { throw EngineError.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw EngineError.localeUnsupported(requestedLocale.identifier)
        }
        try await ensureModelInstalled(for: SpeechTranscriber(locale: locale, preset: preset))
    }

    public func append(_ buffer: PushTextKit.AudioBuffer) async throws {
        guard let continuation, let converter, startedAt != nil else {
            throw EngineError.notStarted
        }

        let converted = try converter.convert(buffer)
        let startTime = CMTime(value: deliveredFrames, timescale: CMTimeScale(targetSampleRate))
        continuation.yield(AnalyzerInput(buffer: converted, bufferStartTime: startTime))
        deliveredFrames += Int64(converted.frameLength)
    }

    public func finishUtterance() async throws -> Transcript {
        guard let startedAt, let analyzer, let resultsTask else { throw EngineError.notStarted }

        continuation?.finish()

        // VoiceInk ships max(20, duration * 4 + 10) as its ceiling (docs/research/01 sec 7). Same
        // shape here: proportional to the audio, with a floor for very short utterances.
        let ceiling = max(20, deliveredSeconds * 4 + 10)

        let text: String
        do {
            try await Self.withTimeout(seconds: ceiling) {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            text = try await Self.withTimeout(seconds: ceiling) { try await resultsTask.value }
        } catch is TimedOut {
            await teardown(cancelling: true)
            throw EngineError.timedOut(seconds: ceiling)
        } catch {
            await teardown(cancelling: true)
            throw error
        }

        let elapsed = ContinuousClock.now - startedAt
        await teardown(cancelling: false)
        return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          duration: elapsed.seconds)
    }

    // MARK: - Internals

    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        // `SpeechTranscriber.installedLocales` is NOT this question - it listed en_US while the
        // module status was .supported and an install was still required (TRAP-21).
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else { return }

        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                // Nothing to install and not installed: not a download problem.
                throw EngineError.modelUnavailable("status \(status), no installation request offered")
            }
            try await request.downloadAndInstall()
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError.modelUnavailable(error.localizedDescription)
        }
    }

    /// Drains the module's results, returning only FINALIZED text.
    ///
    /// Volatile results REPLACE rather than accumulate - each one repeats the tail of the last
    /// finalized result, so appending them duplicates words into the transcript.
    private static func collect(from transcriber: SpeechTranscriber) async throws -> String {
        var finalized = ""
        for try await result in transcriber.results where result.isFinal {
            finalized += String(result.text.characters)
        }
        return finalized
    }

    private func teardown(cancelling: Bool) async {
        if cancelling {
            resultsTask?.cancel()
            if let analyzer { await analyzer.cancelAndFinishNow() }
        }
        continuation = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        startedAt = nil
    }

    struct TimedOut: Error {}

    /// Races `body` against a deadline so a hung stream surfaces as an error instead of a hang.
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimedOut()
            }
            guard let first = try await group.next() else { throw TimedOut() }
            group.cancelAll()
            return first
        }
    }
}
