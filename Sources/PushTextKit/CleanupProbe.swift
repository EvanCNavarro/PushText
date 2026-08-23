import Foundation
import PushTextCore

#if canImport(FoundationModels)
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
/// Activated by `PUSHTEXT_CLEANUP_PROBE=1`. Exits non-zero when the model cannot run, so it is
/// usable as a gate on #14.
public enum CleanupProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_CLEANUP_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        guard #available(macOS 26, *) else {
            print("CLEANUP_PROBE model=skipped reason=requires-macos-26")
            fflush(stdout)
            exit(2)
        }

        let model = SystemLanguageModel.default
        let availability = model.availability

        switch availability {
        case .available:
            print("CLEANUP_PROBE availability=available isAvailable=\(model.isAvailable)")
            print("CLEANUP_PROBE model=ok")
            fflush(stdout)
            exit(0)

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
#endif
