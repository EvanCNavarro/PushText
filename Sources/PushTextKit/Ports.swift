import Foundation
import PushTextCore

// The system boundary. Every OS-touching capability enters the app through one of these, so
// PushTextCore never imports a framework and every adapter is swappable for a fake in tests.
//
// These exist from commit one rather than being extracted later, for two concrete reasons: the
// transcription engine cannot be built on this machine at all until Xcode 26 is installed (so
// Phase 0 runs against MockTranscriptionEngine), and the streaming path we intend to use has an
// open bug on macOS 26.3 — FB22149971, start(inputSequence:) failing with _GenericObjCError —
// which may force a pivot to chunked file-based transcription. A protocol makes that pivot a new
// conformer instead of surgery. See PLAN.md §2.7 and docs/research/01.

// MARK: - Transcription

/// Speech in, text out.
public protocol TranscriptionEngine: Actor {
    /// Whether this engine can run right now on this machine.
    ///
    /// For the Apple engine the real gate is `SpeechTranscriber.isAvailable`, which tracks Neural
    /// Engine core count — NOT whether Apple Intelligence is switched on. An empty
    /// `supportedLocales` is a hardware signal, not a missing download (docs/research/01).
    var isAvailable: Bool { get async }

    /// Get ready to transcribe, off the dictation path (#36).
    ///
    /// Everything slow and one-time belongs here: for the Apple engine that is installing the
    /// on-device model, which `beginUtterance` used to do while the user was already speaking.
    /// Called at launch, and safe to call again - implementations must be idempotent.
    func prepare() async throws

    /// Begin a new utterance. Called on hotkey-down.
    func beginUtterance() async throws

    /// Feed captured audio. Buffers must arrive in order with monotonic timestamps — one of the
    /// three suspected causes of FB22149971 is non-monotonic `bufferStartTime`.
    func append(_ buffer: AudioBuffer) async throws

    /// Close the utterance and return the final transcript.
    ///
    /// Implementations MUST bound their own wait. The Apple result stream is known to hang in the
    /// field; VoiceInk ships `max(20, duration * 4 + 10)` seconds as its ceiling (docs/research/01 §7).
    func finishUtterance() async throws -> Transcript
}

public extension TranscriptionEngine {
    /// Most engines need no preparation; only one has a model to download.
    func prepare() async throws {}
}

/// A finished transcript.
public struct Transcript: Equatable, Sendable {
    /// Final text. Apple's `SpeechTranscriber` already punctuates and capitalizes this — measured
    /// at 99.9% punctuated / 99.7% capitalized across 5,559 published hypotheses (docs/research/06).
    /// That is why cleanup is polish rather than a load-bearing stage.
    public let text: String
    /// Wall-clock seconds from `beginUtterance` to final result. Recorded because no published
    /// SpeechAnalyzer latency figure exists anywhere — we cite our own numbers or none.
    public let duration: TimeInterval

    public init(text: String, duration: TimeInterval) {
        self.text = text
        self.duration = duration
    }
}

/// A chunk of captured audio, opaque to Core.
public struct AudioBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let startTime: TimeInterval

    public init(samples: [Float], sampleRate: Double, startTime: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.startTime = startTime
    }
}

// MARK: - Cleanup

/// Optional LLM polish. Every implementation must be safe to skip.
public protocol CleanupProvider: Actor {
    var isAvailable: Bool { get async }

    /// Polish a transcript. Returning the input unchanged is always a valid answer.
    ///
    /// Callers must treat a throw as "use the raw transcript", never as a user-visible error.
    /// The failure modes here are numerous and mostly invisible in advance: default guardrails
    /// refuse benign prose (4/10 in apfel's own measurement), and `.rateLimited` fires for
    /// backgrounded processes on battery — which describes this app permanently, since a menu-bar
    /// utility is *always* backgrounded. See PLAN.md §2.8, §2.9.
    func clean(_ transcript: Transcript) async throws -> String
}

// MARK: - Input

/// Global push-to-talk key monitoring.
public protocol HotkeyMonitor: AnyObject, Sendable {
    /// Starts observing. Throws if the required permission is absent.
    func start(onEvent: @escaping @Sendable (HotkeyEdge) -> Void) throws
    func stop()
}

/// Microphone capture.
public protocol AudioCapture: AnyObject, Sendable {
    func start(onBuffer: @escaping @Sendable (AudioBuffer) -> Void) throws
    func stop()

    /// What the last utterance lost, if anything (#71).
    ///
    /// On the port rather than the concrete capture because the app has to be able to ASK. The
    /// counters existed on `AVAudioEngineCapture` from #70 and nothing read them - `droppedFrames`
    /// even carries a comment saying it is "surfaced rather than swallowed", which it was not. A
    /// counter no caller can reach is the same silence it was added to break.
    var health: CaptureHealth { get }
}

public extension AudioCapture {
    /// Captures with nothing to lose report nothing lost.
    var health: CaptureHealth { CaptureHealth() }
}

/// Audio the capture could not deliver during one utterance.
///
/// Three separate causes, kept separate because their remedies differ: a device change the engine
/// recovered from, a device change it could NOT recover from, and frames the realtime thread had to
/// discard because the drain fell behind.
public struct CaptureHealth: Equatable, Sendable {
    public var restarts: Int
    public var restartFailures: Int
    public var droppedFrames: Int

    public init(restarts: Int = 0, restartFailures: Int = 0, droppedFrames: Int = 0) {
        self.restarts = restarts
        self.restartFailures = restartFailures
        self.droppedFrames = droppedFrames
    }

    public var isClean: Bool { restarts == 0 && restartFailures == 0 && droppedFrames == 0 }
}

// MARK: - Output

/// Writes text into whatever app currently has focus.
public protocol TextInjector: Sendable {
    /// Injects `text` at the caret of the frontmost app.
    ///
    /// The shipping implementation is pasteboard + synthetic Command-V with a change-count-guarded
    /// restore, NOT an AX write. AX set-text returns *success while doing nothing* in Electron,
    /// VS Code, Google Docs and Pages, and five of five surveyed open-source dictation apps use
    /// the pasteboard route (docs/research/04 §3). Murmur treats AX as primary with pasteboard as
    /// fallback; that is inverted.
    func inject(_ text: String) async throws
}

// MARK: - Permissions

/// Non-prompting permission probes.
///
/// Deliberately does not include Input Monitoring: `CGRequestListenEventAccess` is a permission
/// request, not a detection mechanism, and the OS's own `TCCServiceList.plist` marks that service
/// `requiresAdmin => 1` while Accessibility carries no such flag (docs/research/04 §4).
public protocol PermissionProbe: Sendable {
    func status(of permission: Permission) -> PermissionStatus
}

public enum Permission: CaseIterable, Sendable {
    case microphone
    case accessibility
    /// A separate TCC service from Accessibility despite sharing one toggle in System Settings.
    case postEvent
}

public enum PermissionStatus: Equatable, Sendable {
    case granted
    /// Never asked. Prompt is appropriate.
    case needsFirstGrant
    /// Was granted once and is now not — usually a code-signature change. Repair, don't re-prompt.
    case grantBroken
    case denied
}
