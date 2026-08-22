import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

@Suite("MockTranscriptionEngine")
struct MockTranscriptionEngineTests {

    @Test("Counts the audio it was fed, so a dead capture path is visible")
    func countsBuffers() async throws {
        let engine = MockTranscriptionEngine(
            configuration: .init(latency: .milliseconds(1)))
        try await engine.beginUtterance()
        for i in 0..<3 {
            try await engine.append(
                AudioBuffer(samples: Array(repeating: 0.0, count: 512),
                            sampleRate: 16_000,
                            startTime: Double(i) * 0.032))
        }
        _ = try await engine.finishUtterance()

        #expect(await engine.lastBufferCount == 3)
        #expect(await engine.lastSampleCount == 1536)
    }

    @Test("Appending before beginUtterance throws rather than silently succeeding")
    func appendBeforeBeginThrows() async {
        let engine = MockTranscriptionEngine()
        await #expect(throws: MockTranscriptionEngine.MockError.notStarted) {
            try await engine.append(
                AudioBuffer(samples: [0], sampleRate: 16_000, startTime: 0))
        }
    }

    @Test("Consecutive utterances return different phrases, so a stuck result is detectable")
    func cyclesPhrases() async throws {
        let engine = MockTranscriptionEngine(
            configuration: .init(phrases: ["one", "two"], latency: .milliseconds(1)))
        var seen: [String] = []
        for _ in 0..<3 {
            try await engine.beginUtterance()
            seen.append(try await engine.finishUtterance().text)
        }
        #expect(seen == ["one", "two", "one"])
    }

    @Test("The failure path actually throws")
    func simulatedFailure() async throws {
        let engine = MockTranscriptionEngine(
            configuration: .init(latency: .milliseconds(1), shouldFail: true))
        try await engine.beginUtterance()
        await #expect(throws: MockTranscriptionEngine.MockError.simulatedFailure) {
            _ = try await engine.finishUtterance()
        }
    }

    @Test("Reports a non-zero measured duration")
    func reportsDuration() async throws {
        let engine = MockTranscriptionEngine(
            configuration: .init(latency: .milliseconds(20)))
        try await engine.beginUtterance()
        let transcript = try await engine.finishUtterance()
        #expect(transcript.duration > 0)
    }
}
