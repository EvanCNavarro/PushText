// Spike for PushText issue #11: does SpeechAnalyzer.start(inputSequence:) work on this Tahoe build?
//
// FB22149971 reports `_GenericObjCError ... nilError` from the STREAMING entry point on macOS 26.3,
// while batch transcription succeeds on identical audio. This binary runs exactly that A/B: same
// transcriber preset, same locale, same PCM buffers, same chunk size - the ONLY difference between
// the two arms is `start(inputSequence:)` versus `analyzeSequence(_:)`.
//
// Arms (argv[1]): env | batch | streaming
// argv[2] = frames per buffer (default 4096; the radar suspects sub-4096 buffers as a trigger)
//
// Every arm prints a single VERDICT= line so the result cannot be confused with narration.

import AVFoundation
import Foundation
import Speech

// MARK: - Reporting

func note(_ message: String) {
    print("[spike] \(message)")
    fflush(stdout)
}

/// Prints an error with the ObjC bridging detail that distinguishes FB22149971 from an ordinary
/// setup failure. A bare `\(error)` renders the radar's case as the useless string "The operation
/// couldn't be completed", which is exactly how this bug gets misattributed.
func describe(_ error: Error) -> String {
    let ns = error as NSError
    var parts = [
        "swift=\(error)",
        "domain=\(ns.domain)",
        "code=\(ns.code)"
    ]
    if !ns.userInfo.isEmpty {
        parts.append("userInfo=\(ns.userInfo)")
    }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] {
        parts.append("underlying=\(underlying)")
    }
    return parts.joined(separator: " | ")
}

struct TimedOut: Error {}

/// Races `body` against a deadline. #12's backlog note says the results stream hangs in the field,
/// so an un-timed await here would report a hang as an indefinite wait rather than as a result.
func withTimeout<T: Sendable>(
    seconds: Double,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimedOut()
        }
        guard let first = try await group.next() else { throw TimedOut() }
        group.cancelAll()
        return first
    }
}

// MARK: - Audio

/// Reads the WAV and converts it to `target`, returning fixed-size buffers.
/// Buffers carry monotonic, contiguous start times derived from a running frame count - the same
/// construction PushText's AudioRingBuffer uses, which is why the radar's third suspected cause
/// (non-monotonic bufferStartTime) is already excluded here by design rather than by luck.
func convertToTarget(url: URL, target: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: url)
    let source = file.processingFormat

    guard let converter = AVAudioConverter(from: source, to: target) else {
        throw NSError(domain: "spike", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "no converter from \(source) to \(target)"
        ])
    }

    guard let inBuffer = AVAudioPCMBuffer(
        pcmFormat: source,
        frameCapacity: AVAudioFrameCount(file.length)
    ) else {
        throw NSError(domain: "spike", code: 2, userInfo: [NSLocalizedDescriptionKey: "input buffer alloc failed"])
    }
    try file.read(into: inBuffer)

    let ratio = target.sampleRate / source.sampleRate
    let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 4096
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        throw NSError(domain: "spike", code: 3, userInfo: [NSLocalizedDescriptionKey: "output buffer alloc failed"])
    }

    var supplied = false
    var conversionError: NSError?
    converter.convert(to: outBuffer, error: &conversionError) { _, status in
        if supplied {
            status.pointee = .endOfStream
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return inBuffer
    }
    if let conversionError { throw conversionError }

    note("converted \(inBuffer.frameLength) frames @ \(source.sampleRate)Hz"
         + " -> \(outBuffer.frameLength) frames @ \(target.sampleRate)Hz")
    return outBuffer
}

/// Slices a converted buffer into fixed-size inputs with contiguous timestamps.
func loadBuffers(url: URL, target: AVAudioFormat, framesPerBuffer: AVAudioFrameCount) throws -> [AnalyzerInput] {
    let outBuffer = try convertToTarget(url: url, target: target)
    var inputs: [AnalyzerInput] = []
    var offset: AVAudioFrameCount = 0
    var frameCounter: Int64 = 0

    while offset < outBuffer.frameLength {
        let count = min(framesPerBuffer, outBuffer.frameLength - offset)
        guard let slice = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: count) else { break }
        slice.frameLength = count

        let channels = Int(target.channelCount)
        if let src = outBuffer.floatChannelData, let dst = slice.floatChannelData {
            for channel in 0..<channels {
                memcpy(dst[channel], src[channel] + Int(offset), Int(count) * MemoryLayout<Float>.size)
            }
        } else if let src = outBuffer.int16ChannelData, let dst = slice.int16ChannelData {
            for channel in 0..<channels {
                memcpy(dst[channel], src[channel] + Int(offset), Int(count) * MemoryLayout<Int16>.size)
            }
        } else {
            throw NSError(domain: "spike", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "unsupported sample format \(target.commonFormat.rawValue)"
            ])
        }

        let startTime = CMTime(value: frameCounter, timescale: CMTimeScale(target.sampleRate))
        inputs.append(AnalyzerInput(buffer: slice, bufferStartTime: startTime))

        frameCounter += Int64(count)
        offset += count
    }

    return inputs
}

// MARK: - Setup shared by both arms

struct Rig {
    let transcriber: SpeechTranscriber
    let locale: Locale
    let format: AVAudioFormat
}

func buildRig() async throws -> Rig {
    note("SpeechTranscriber.isAvailable = \(SpeechTranscriber.isAvailable)")

    let requested = Locale(identifier: "en-US")
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
        let supported = await SpeechTranscriber.supportedLocales
        throw NSError(domain: "spike", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "en-US unsupported; supported=\(supported.map(\.identifier))"
        ])
    }
    note("locale resolved: \(locale.identifier)")

    // .progressiveTranscription is what a push-to-talk dictation app needs (volatile partials).
    // Both arms use it, so the preset is held constant across the A/B.
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

    let status = await AssetInventory.status(forModules: [transcriber])
    note("AssetInventory.status = \(status)")

    // A missing model throws from deep inside the analyzer and is easy to misread as the radar bug.
    // Install it explicitly first so that ambiguity is removed before either arm runs.
    if status != .installed {
        note("model not installed - requesting installation")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
            note("downloadAndInstall returned; status now \(await AssetInventory.status(forModules: [transcriber]))")
        } else {
            note("assetInstallationRequest returned nil (nothing to install)")
        }
    }

    let reserved = try await AssetInventory.reserve(locale: locale)
    let reservedNow = await AssetInventory.reservedLocales.map(\.identifier)
    note("AssetInventory.reserve(locale:) = \(reserved); reservedLocales=\(reservedNow)")

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
        throw NSError(domain: "spike", code: 11, userInfo: [NSLocalizedDescriptionKey: "no compatible audio format"])
    }
    note("bestAvailableAudioFormat = \(format.sampleRate)Hz ch=\(format.channelCount)"
         + " common=\(format.commonFormat.rawValue)")

    return Rig(transcriber: transcriber, locale: locale, format: format)
}

/// Drains `transcriber.results` until the stream ends, returning the finalized text.
func collectResults(_ transcriber: SpeechTranscriber) async throws -> String {
    var finalized = ""
    var volatileCount = 0
    for try await result in transcriber.results {
        let text = String(result.text.characters)
        if result.isFinal {
            finalized += text
            note("final: \"\(text)\"")
        } else {
            volatileCount += 1
            if volatileCount <= 3 {
                note("volatile: \"\(text)\"")
            }
        }
    }
    note("results stream ended; volatile results seen = \(volatileCount)")
    return finalized
}

// MARK: - Arms

func runBatch(framesPerBuffer: AVAudioFrameCount, url: URL) async {
    do {
        let rig = try await buildRig()
        let inputs = try loadBuffers(url: url, target: rig.format, framesPerBuffer: framesPerBuffer)
        note("prepared \(inputs.count) buffers of \(framesPerBuffer) frames")

        let analyzer = SpeechAnalyzer(modules: [rig.transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        for input in inputs { continuation.yield(input) }
        continuation.finish()

        let transcriber = rig.transcriber
        let collected = Task { try await collectResults(transcriber) }

        let last = try await withTimeout(seconds: 120) {
            try await analyzer.analyzeSequence(stream)
        }
        note("analyzeSequence returned last time = \(String(describing: last))")
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collected.value
        print("VERDICT=BATCH_OK text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
    } catch {
        print("VERDICT=BATCH_FAILED \(describe(error))")
    }
}

func runStreaming(framesPerBuffer: AVAudioFrameCount, url: URL) async {
    do {
        let rig = try await buildRig()
        let inputs = try loadBuffers(url: url, target: rig.format, framesPerBuffer: framesPerBuffer)
        note("prepared \(inputs.count) buffers of \(framesPerBuffer) frames")

        let analyzer = SpeechAnalyzer(modules: [rig.transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let transcriber = rig.transcriber
        let collected = Task { try await collectResults(transcriber) }

        // THE CALL UNDER TEST.
        note("calling start(inputSequence:) ...")
        try await withTimeout(seconds: 60) {
            try await analyzer.start(inputSequence: stream)
        }
        note("start(inputSequence:) returned without throwing")

        // Feed at roughly real time, as a live microphone would - the radar is about the streaming
        // path, and dumping every buffer instantly would not exercise it the way capture does.
        let secondsPerBuffer = Double(framesPerBuffer) / rig.format.sampleRate
        for input in inputs {
            continuation.yield(input)
            try await Task.sleep(nanoseconds: UInt64(secondsPerBuffer * 1_000_000_000))
        }
        continuation.finish()
        note("fed \(inputs.count) buffers; finalizing")

        try await withTimeout(seconds: 60) {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        let text = try await withTimeout(seconds: 60) { try await collected.value }
        print("VERDICT=STREAMING_OK text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
    } catch {
        print("VERDICT=STREAMING_FAILED \(describe(error))")
    }
}

/// PLANT: feeds buffers in the wrong sample rate on purpose. Exists solely to prove that a failure
/// originating INSIDE SpeechAnalyzer - not in this file's own IO - reaches the VERDICT line.
func runStreamingBadFormat(framesPerBuffer: AVAudioFrameCount, url: URL) async {
    do {
        let rig = try await buildRig()
        let wrong = try AVAudioFile(forReading: url).processingFormat
        note("PLANT: analyzer expects \(rig.format.sampleRate)Hz, feeding \(wrong.sampleRate)Hz")
        let inputs = try loadBuffers(url: url, target: wrong, framesPerBuffer: framesPerBuffer)

        let analyzer = SpeechAnalyzer(modules: [rig.transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let transcriber = rig.transcriber
        let collected = Task { try await collectResults(transcriber) }

        try await withTimeout(seconds: 60) {
            try await analyzer.start(inputSequence: stream)
        }
        for input in inputs { continuation.yield(input) }
        continuation.finish()
        try await withTimeout(seconds: 60) {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        let text = try await withTimeout(seconds: 60) { try await collected.value }
        print("VERDICT=PLANT_NOT_DETECTED text=\"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
    } catch {
        print("VERDICT=PLANT_DETECTED \(describe(error))")
    }
}

func runEnv() async {
    let info = ProcessInfo.processInfo.operatingSystemVersion
    note("macOS \(info.majorVersion).\(info.minorVersion).\(info.patchVersion)")
    note("SpeechTranscriber.isAvailable = \(SpeechTranscriber.isAvailable)")
    let supported = await SpeechTranscriber.supportedLocales
    let installed = await SpeechTranscriber.installedLocales
    note("supportedLocales (\(supported.count)): \(supported.prefix(8).map(\.identifier))")
    note("installedLocales (\(installed.count)): \(installed.map(\.identifier))")
    note("maximumReservedLocales = \(AssetInventory.maximumReservedLocales)")
    note("reservedLocales = \(await AssetInventory.reservedLocales.map(\.identifier))")
    print("VERDICT=ENV_OK")
}

// MARK: - Entry

let arm = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "env"
let frames = AVAudioFrameCount(CommandLine.arguments.count > 2 ? (UInt32(CommandLine.arguments[2]) ?? 4096) : 4096)
let audioURL = URL(fileURLWithPath: CommandLine.arguments.count > 3
    ? CommandLine.arguments[3]
    : FileManager.default.currentDirectoryPath + "/sample.wav")

note("arm=\(arm) framesPerBuffer=\(frames) audio=\(audioURL.path)")

switch arm {
case "env": await runEnv()
case "batch": await runBatch(framesPerBuffer: frames, url: audioURL)
case "streaming": await runStreaming(framesPerBuffer: frames, url: audioURL)
case "streaming-badformat": await runStreamingBadFormat(framesPerBuffer: frames, url: audioURL)
default:
    print("VERDICT=BAD_ARM \(arm)")
    exit(2)
}
