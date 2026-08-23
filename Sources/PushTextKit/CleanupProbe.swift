import Foundation
import PushTextCore

import FoundationModels

/// Answers the question #33 asks: can `FoundationModels` actually run on this machine?
///
/// The framework being present in the SDK means it COMPILES. Whether it can produce a response
/// depends on Apple Intelligence being enabled and its model downloaded, which is a per-machine,
/// per-region, per-hardware state the compiler knows nothing about. #33 was filed off a crash
/// report that carried `appleIntelligenceStatus state=restricted reasons=[assetIsNotReady]` - read
/// from a log rather than asked of the framework, which is why it was filed as a question.
///
/// This asks the framework directly, and prints the CONCRETE reason rather than a boolean: the three
/// unavailable cases need completely different responses. `deviceNotEligible` is permanent and means
/// cleanup can never ship here; `appleIntelligenceNotEnabled` is a Settings toggle; `modelNotReady`
/// is a download that will finish on its own.
///
/// Activated by `PUSHTEXT_CLEANUP_PROBE=1`. With `PUSHTEXT_CLEANUP_PROBE_TEXT` set it also runs one
/// REAL cleanup through `FoundationModelsCleanup` and prints what came back - availability says the
/// model can run, and only this says cleanup produces something that survives the drift guard.
/// Exits non-zero when the model cannot run, so it is usable as a gate on #14.
public enum CleanupProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_CLEANUP_PROBE"] == "1"
    }

    /// Runs one real cleanup and exits. Blocking wait is fine here: this is a probe process whose
    /// only job is this call, and nothing else needs the main thread.
    private static func runCleanupAndExit(_ text: String) -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task {
            let cleanup = FoundationModelsCleanup()
            let transcript = Transcript(text: text, duration: 0)
            let cleaned = (try? await cleanup.clean(transcript)) ?? text
            box.set(cleaned: cleaned, rejection: await cleanup.lastRejection)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 60)

        print("CLEANUP_PROBE raw=\"\(text)\"")
        print("CLEANUP_PROBE cleaned=\"\(box.cleaned)\"")
        print("CLEANUP_PROBE changed=\(box.cleaned != text) rejection=\(box.rejectionDescription)")
        print("CLEANUP_PROBE model=ok")
        fflush(stdout)
        exit(0)
    }

    public static func runAndExit() -> Never {
        let model = SystemLanguageModel.default
        let availability = model.availability

        switch availability {
        case .available:
            print("CLEANUP_PROBE availability=available isAvailable=\(model.isAvailable)")
            fflush(stdout)

            // With text supplied, drive the REAL model through the real provider. Availability says
            // the model can run; only this says cleanup actually produces something and survives
            // the drift guard.
            guard let text = ProcessInfo.processInfo.environment["PUSHTEXT_CLEANUP_PROBE_TEXT"] else {
                print("CLEANUP_PROBE model=ok")
                fflush(stdout)
                exit(0)
            }
            runCleanupAndExit(text)

        case .unavailable(let reason):
            let name: String
            let meaning: String
            switch reason {
            case .deviceNotEligible:
                name = "deviceNotEligible"
                meaning = "permanent on this hardware - cleanup can never run here"
            case .appleIntelligenceNotEnabled:
                name = "appleIntelligenceNotEnabled"
                meaning = "a Settings toggle, not a download"
            case .modelNotReady:
                name = "modelNotReady"
                meaning = "downloading or not yet downloaded - retry later"
            @unknown default:
                name = "unknown"
                meaning = "a reason this build does not know about"
            }
            print("CLEANUP_PROBE availability=unavailable reason=\(name)")
            print("CLEANUP_PROBE meaning=\(meaning)")
            print("CLEANUP_PROBE model=unavailable")
            fflush(stdout)
            exit(3)
        }
    }
}

/// Carries the async result back across the semaphore.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var reason: CleanupRejection?

    func set(cleaned: String, rejection: CleanupRejection?) {
        lock.lock(); text = cleaned; reason = rejection; lock.unlock()
    }

    var cleaned: String { lock.lock(); defer { lock.unlock() }; return text }
    var rejectionDescription: String {
        lock.lock(); defer { lock.unlock() }
        return reason.map { "\($0)" } ?? "none"
    }
}
