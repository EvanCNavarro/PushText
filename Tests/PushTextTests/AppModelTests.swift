import Testing
import Foundation
import PushTextCore
import PushTextKit
@testable import PushText

/// Covers the shell's only real logic: turning machine state into what the user sees, and turning a
/// raw key edge into a dictation event.
///
/// This target also exists for a duller reason worth recording. It was declared in Package.swift
/// with an EMPTY directory, and git does not track empty directories — so every local build passed
/// while a fresh clone (and therefore CI) failed with "Source files for target PushTextTests should
/// be located under 'Tests/PushTextTests'". A test target with no tests is not a neutral placeholder.
@MainActor
@Suite("AppModel")
struct AppModelTests {

    private func makeModel() -> AppModel {
        AppModel(engine: MockTranscriptionEngine())
    }

    @Test("A fresh model is idle and reports Ready")
    func startsIdle() {
        let model = makeModel()
        #expect(model.machine.state == .idle)
        #expect(model.statusText == "Ready")
        #expect(model.menuBarGlyph == .idle)
    }

    @Test("A key press maps to hotkeyPressed and the menu bar mark changes")
    func pressStartsCapture() {
        let model = makeModel()
        model.handle(.pressed, at: 0)
        #expect(model.machine.state == .arming)
        #expect(model.machine.isCapturing)
        #expect(model.menuBarGlyph == .active)
        #expect(model.statusText == "Starting...")
    }

    @Test("A key release during recording moves to transcribing and stops capturing")
    func releaseEndsCapture() {
        let model = makeModel()
        model.handle(.pressed, at: 0)
        model.apply(.audioStarted)
        #expect(model.statusText == "Listening")

        model.handle(.released, at: 1)
        #expect(model.machine.state == .transcribing)
        #expect(!model.machine.isCapturing)
        #expect(model.menuBarGlyph == .idle)
    }

    /// The menu row is hidden while idle (#128), because "Ready" is what it said every time anyone
    /// opened the menu - you cannot be mid-dictation and clicking the menu bar, except in the
    /// latched mode.
    @Test("Idle reports no activity, so the menu shows no State row")
    func idleHasNoActivity() {
        let model = makeModel()
        #expect(model.machine.state == .idle)
        #expect(model.activityText == nil)
    }

    /// Hiding the row must not hide a FAILURE. `MenuContent` is the only surface in the app that
    /// shows a `DictationFailure` - the HUD has no phase for one - so if any of these went nil the
    /// message would have nowhere left to appear.
    @Test("Every non-idle state still reports activity, failures included")
    func everyNonIdleStateReportsActivity() {
        let states: [DictationState] = [
            .arming, .recording, .transcribing, .cleaning, .injecting,
            .failed(.permissionDenied), .failed(.noSpeechDetected), .failed(.modelNotReady),
            .failed(.transcriptionFailed), .failed(.injectionFailed), .failed(.cancelled)
        ]
        for state in states {
            let model = AppModel(engine: MockTranscriptionEngine(),
                                 machine: DictationMachine(state: state))
            #expect(model.activityText == model.statusText, "\(state) lost its message")
            #expect(model.activityText?.isEmpty == false, "\(state) reports nothing")
        }
    }

    @Test("Every dictation state produces a non-empty, distinct-enough status string")
    func statusTextCoversEveryState() {
        let states: [DictationState] = [
            .idle, .arming, .recording, .transcribing, .cleaning, .injecting,
            .failed(.permissionDenied), .failed(.noSpeechDetected),
            .failed(.transcriptionFailed), .failed(.injectionFailed), .failed(.cancelled)
        ]
        var seen: Set<String> = []
        for state in states {
            let model = AppModel(engine: MockTranscriptionEngine(), machine: DictationMachine(state: state))
            let text = model.statusText
            #expect(!text.isEmpty, "state \(state) produced an empty status")
            seen.insert(text)
        }
        // Each failure reason must read differently; a single "Error" for all of them would pass an
        // is-not-empty check while telling the user nothing.
        #expect(seen.count == states.count)
    }

    @Test("A failure is terminal and surfaces its own message")
    func failureSurfaces() {
        let model = makeModel()
        model.handle(.pressed, at: 0)
        model.apply(.failure(.permissionDenied))
        #expect(model.machine.isTerminal)
        #expect(model.statusText == "Permission needed")
    }
}

@MainActor
@Suite("AppModel capture watchdog")
struct AppModelWatchdogTests {

    private func makeModel(maxDuration: TimeInterval) -> AppModel {
        let model = AppModel(engine: MockTranscriptionEngine())
        model.maximumCaptureDuration = maxDuration
        return model
    }

    @Test("The watchdog arms when capture starts and disarms when it ends")
    func armsAndDisarms() {
        let model = makeModel(maxDuration: 120)
        #expect(!model.isCaptureWatchdogArmed)

        model.handle(.pressed, at: 0)
        #expect(model.isCaptureWatchdogArmed)

        model.handle(.released, at: 1)
        #expect(!model.isCaptureWatchdogArmed)
    }

    /// The ceiling is a PRODUCT decision and it regressed once already (#197).
    ///
    /// At 120 s a hands-free dictation died mid-sentence and every word was thrown away. The number
    /// is asserted here so that lowering it is a deliberate act with a failing test attached, rather
    /// than a quiet edit to a constant.
    @Test("A dictation may run for twenty minutes before the watchdog steps in")
    func watchdogCeilingIsGenerous() {
        let model = AppModel(engine: MockTranscriptionEngine())
        #expect(model.maximumCaptureDuration >= 1200,
                "a hands-free dictation would be cut off after \(model.maximumCaptureDuration)s")
    }

    /// The case no flag-state recovery can reach: a stalled tap drops the key-up so completely that
    /// macOS's own flagsState stays latched. Only elapsed time can close it.
    @Test("A capture whose release never arrives is force-closed by elapsed time")
    func forceClosesStuckCapture() async throws {
        let model = makeModel(maxDuration: 0.2)
        model.handle(.pressed, at: 0)
        model.apply(.audioStarted)
        #expect(model.machine.isCapturing)

        try await Task.sleep(for: .milliseconds(500))

        #expect(!model.machine.isCapturing, "the microphone was still open after the watchdog window")
        // NOT `.failed(.cancelled)` (#197). The watchdog closes the microphone and hands what it
        // heard to the transcriber; this model's engine returns nothing for an empty capture, so it
        // lands on `.failed(.transcriptionFailed)` - the point is that it went through TRANSCRIBING
        // rather than throwing the audio away.
        //
        // This assertion used to read `.failed(.cancelled)` and it codified real data loss: Bobby
        // spoke for over two minutes and every word was discarded by a timer.
        #expect(model.machine.state != .failed(.cancelled),
                "the watchdog cancelled instead of transcribing - the user loses everything")
        #expect(!model.isCaptureWatchdogArmed)
    }

    @Test("A capture that ends normally is never force-closed")
    func normalCaptureSurvives() async throws {
        let model = makeModel(maxDuration: 0.2)
        model.handle(.pressed, at: 0)
        model.apply(.audioStarted)
        model.handle(.released, at: 1)
        #expect(model.machine.state == .transcribing)

        try await Task.sleep(for: .milliseconds(400))

        // Assert what this test is ACTUALLY about: the watchdog did not force-close a capture that
        // ended normally. It must NOT assert `.transcribing`, which was a race - the mock engine's
        // default latency is also 400 ms, so the pipeline may legitimately have advanced to
        // cleaning, injecting or idle by now. That assertion passed locally and failed on CI on a
        // coin flip, and it was never the property under test.
        #expect(model.machine.state != .failed(.cancelled),
                "the watchdog fired after capture had already ended")
        #expect(!model.isCaptureWatchdogArmed, "the watchdog stayed armed after capture ended")
    }

    @Test("A zero duration disables the watchdog entirely")
    func zeroDurationDisables() {
        let model = makeModel(maxDuration: 0)
        model.handle(.pressed, at: 0)
        #expect(!model.isCaptureWatchdogArmed)
    }
}
