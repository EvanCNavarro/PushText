// Spike for PushText issue #13: does `AnalysisContext.contextualStrings` bias `SpeechTranscriber`?
//
// docs/research/01 sec 1.6 says to treat custom vocabulary on SpeechTranscriber as "UNVERIFIED and
// probably absent": a forum responder reports it works with DictationTranscriber but not
// SpeechTranscriber, and Argmax independently reports SpeechAnalyzer "lacks the Custom Vocabulary
// feature". Both are REPORTS. This executes it.
//
// The A/B holds everything constant except the context: same audio buffers, same transcriber preset,
// same locale, same chunking. Only `contextualStrings` differs. If the two transcripts are identical
// the biasing had no effect, which is the outcome the research predicts.
//
// Arms (argv[1]): plain | biased | both

import AVFoundation
import Foundation
import Speech

func note(_ message: String) {
    print("[spike13] \(message)")
    fflush(stdout)
}

/// The words the bias is supposed to favour. Chosen to be things a general vocabulary will not have:
/// a camel-case product name and a coined company name.
let biasWords = ["PushText", "Invela", "Kubernetes"]

struct TimedOut: Error {}

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

func loadBuffers(url: URL, target: AVAudioFormat, framesPerBuffer: AVAudioFrameCount = 4096)
    throws -> [AnalyzerInput] {
    let file = try AVAudioFile(forReading: url)
    let source = file.processingFormat

    guard let converter = AVAudioConverter(from: source, to: target),
          let input = AVAudioPCMBuffer(pcmFormat: source,
                                       frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "spike13", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot prepare conversion"])
    }
    try file.read(into: input)

    let ratio = target.sampleRate / source.sampleRate
    let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
        throw NSError(domain: "spike13", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "output alloc failed"])
    }

    var supplied = false
    var conversionError: NSError?
    converter.convert(to: output, error: &conversionError) { _, status in
        if supplied { status.pointee = .endOfStream; return nil }
        supplied = true
        status.pointee = .haveData
        return input
    }
    if let conversionError { throw conversionError }

    var inputs: [AnalyzerInput] = []
    var offset: AVAudioFrameCount = 0
    var frames: Int64 = 0
    while offset < output.frameLength {
        let count = min(framesPerBuffer, output.frameLength - offset)
        guard let slice = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: count) else { break }
        slice.frameLength = count
        if let src = output.int16ChannelData, let dst = slice.int16ChannelData {
            memcpy(dst[0], src[0] + Int(offset), Int(count) * MemoryLayout<Int16>.size)
        } else if let src = output.floatChannelData, let dst = slice.floatChannelData {
            memcpy(dst[0], src[0] + Int(offset), Int(count) * MemoryLayout<Float>.size)
        }
        inputs.append(AnalyzerInput(buffer: slice,
                                    bufferStartTime: CMTime(value: frames,
                                                            timescale: CMTimeScale(target.sampleRate))))
        frames += Int64(count)
        offset += count
    }
    return inputs
}

func collect(_ transcriber: SpeechTranscriber) async throws -> String {
    var finalized = ""
    for try await result in transcriber.results where result.isFinal {
        finalized += String(result.text.characters)
    }
    return finalized
}

/// One transcription of `url`, optionally with contextual strings applied.
func transcribe(url: URL, biased: Bool) async throws -> String {
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
        throw NSError(domain: "spike13", code: 10,
                      userInfo: [NSLocalizedDescriptionKey: "en-US unsupported"])
    }
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

    if await AssetInventory.status(forModules: [transcriber]) != .installed,
       let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        try await request.downloadAndInstall()
    }
    _ = try? await AssetInventory.reserve(locale: locale)

    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
        throw NSError(domain: "spike13", code: 11,
                      userInfo: [NSLocalizedDescriptionKey: "no compatible format"])
    }

    // THE ONLY DIFFERENCE between the two arms.
    let context = AnalysisContext()
    if biased {
        context.contextualStrings[.general] = biasWords
        note("context set: \(biasWords)")
    }

    let inputs = try loadBuffers(url: url, target: format)
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let analyzer = SpeechAnalyzer(inputSequence: stream,
                                  modules: [transcriber],
                                  analysisContext: context)

    let collected = Task { try await collect(transcriber) }
    for input in inputs { continuation.yield(input) }
    continuation.finish()

    try await withTimeout(seconds: 90) {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }
    return try await withTimeout(seconds: 90) { try await collected.value }
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Entry

let arm = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "both"
let audio = URL(fileURLWithPath: CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : FileManager.default.currentDirectoryPath + "/sample.wav")

note("arm=\(arm) audio=\(audio.path)")

do {
    switch arm {
    case "plain":
        let text = try await transcribe(url: audio, biased: false)
        print("VERDICT=PLAIN text=\"\(text)\"")

    case "biased":
        let text = try await transcribe(url: audio, biased: true)
        print("VERDICT=BIASED text=\"\(text)\"")

    case "both":
        let plain = try await transcribe(url: audio, biased: false)
        let biased = try await transcribe(url: audio, biased: true)
        print("VERDICT=PLAIN  text=\"\(plain)\"")
        print("VERDICT=BIASED text=\"\(biased)\"")
        print("VERDICT=IDENTICAL=\(plain == biased)")
        // Whether the bias words appear at all is the question behind the question: identical
        // transcripts prove no effect, and a biased transcript containing the words proves one.
        let hits = biasWords.filter { biased.localizedCaseInsensitiveContains($0) }
        print("VERDICT=BIAS_WORDS_PRESENT=\(hits)")

    default:
        print("VERDICT=BAD_ARM \(arm)")
        exit(2)
    }
} catch {
    let ns = error as NSError
    print("VERDICT=FAILED swift=\(error) | domain=\(ns.domain) | code=\(ns.code)")
    exit(3)
}
