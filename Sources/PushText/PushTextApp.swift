import SwiftUI
import AVFoundation
import OSLog
import PushTextCore
import PushTextKit

/// Diagnostics for a menu-bar app that otherwise runs silently.
///
/// Without this, "the hotkey never fired", "the engine refused" and "the text was pasted and the
/// target ignored it" are indistinguishable from the outside - the app has no console, no window
/// and, until #7 ships a HUD, no visible state beyond a menu-bar glyph. Read live with:
///
///     log stream --predicate 'subsystem == "dev.ecn.apps.pushtext"' --info
let dictationLog = Logger(subsystem: "dev.ecn.apps.pushtext", category: "dictation")

/// Runs work that must happen after AppKit is up, so a permission prompt has a running app to
/// appear over rather than being raised from `App.init()` before `NSApplicationMain`.
///
/// NOT the reason the microphone was failing, though it was my first guess. Moving the request here
/// changed nothing; `tccd` named the real cause - a missing `com.apple.security.device.audio-input`
/// entitlement under the hardened runtime (TRAP-27). Kept because it is still the correct lifecycle
/// for a prompt, and recorded here so the next reader does not re-derive the wrong explanation.
final class LaunchDelegate: NSObject, NSApplicationDelegate {
    var onLaunch: (@Sendable () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        onLaunch?()
    }
}

/// Composition root. Every dependency is constructed here and injected downward, so nothing
/// deeper in the app reaches for a singleton or a framework on its own.
@main
struct PushTextApp: App {
    @NSApplicationDelegateAdaptor(LaunchDelegate.self) private var launchDelegate
    @State private var model: AppModel
    /// Held for the process lifetime: releasing the monitor tears down the event tap.
    private let hotkey: CGEventTapHotkeyMonitor
    /// Owns the Sparkle updater, so it outlives the menu being opened and closed.
    private let actions = AppActions()

    init() {
        // Headless proof of the event tap, before any UI exists. Never returns when requested.
        if HotkeyProbe.isRequested {
            HotkeyProbe.runAndExit()
        }
        if AudioProbe.isRequested {
            AudioProbe.runAndExit()
        }
        if InjectionProbe.isRequested {
            InjectionProbe.runAndExit()
        }
        // Gated on the SDK, not the OS: TranscriptionProbe drives SpeechAnalyzer, whose symbols do
        // not exist when building against an older SDK (CI's macos-15 runner).
        #if canImport(FoundationModels)
        if TranscriptionProbe.isRequested {
            TranscriptionProbe.runAndExit()
        }
        #endif
        // No probe took over, so any probe-tuning variable still set is a misconfiguration that
        // would otherwise launch the UI and look like a hung probe.
        ProbeActivation.enforceOrExit()

        // Phase 1 wiring (#12, #39): Apple's on-device SpeechAnalyzer, now that Xcode 26 ships the
        // SDK and #11 confirmed the streaming path works on this OS build. Systems that cannot run
        // it get an engine that REFUSES rather than the mock, whose canned phrases would otherwise
        // be typed into a real document — see TranscriptionEngineFactory.
        let model = AppModel(engine: TranscriptionEngineFactory.makeDefault(),
                             capture: AVAudioEngineCapture(),
                             injector: PasteboardTextInjector(),
                             indicator: DictationHUDController())
        self.model = model

        // The tap is the only thing that can fail at launch, and it fails for one reason worth
        // telling the user about: Accessibility is not granted. Surfaced in the menu rather than
        // thrown, because a menu-bar app that crashes on launch gives them nothing to act on.
        let monitor = CGEventTapHotkeyMonitor()
        self.hotkey = monitor
        do {
            try monitor.start { edge in
                dictationLog.info("hotkey edge=\(String(describing: edge), privacy: .public)")
                Task { @MainActor in model.handle(edge) }
            }
            dictationLog.info("hotkey tap armed")
        } catch {
            dictationLog.error("hotkey tap FAILED: \(String(describing: error), privacy: .public)")
            model.reportStartupFailure(
                "Hold-to-dictate needs Accessibility. Grant it in System Settings > Privacy & "
                + "Security > Accessibility, then relaunch PushText.")
        }

        launchDelegate.onLaunch = { Self.requestMicrophone(for: model) }

        // Visual verification hook (#46). UI cannot be proven by a unit test - this shows the HUD
        // at a fixed level so it can be screenshotted and judged. Deliberately NOT animated: a
        // moving demo would flatter the design and hide what a real, mostly-quiet level looks like.
        if ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE"] == "1" {
            let level = Double(ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE_LEVEL"] ?? "") ?? 0.6
            launchDelegate.onLaunch = {
                Task { @MainActor in
                    // Wait for the status item to exist: MenuBarExtra creates it after launch, and
                    // anchoring before it exists is what sent the first probe to the fallback.
                    try? await Task.sleep(for: .seconds(2))
                    let hud = DictationHUDController()
                    hud.show(phase: .recording, onCancel: {}, onConfirm: {})
                    hud.update(phase: .recording, level: level)
                    dictationLog.info("HUD_PROBE showing level=\(level)")
                }
            }
        }
    }

    /// Asks for the microphone once AppKit is running.
    ///
    /// Not on first key press: a prompt raised mid-utterance would eat the words the user is
    /// already speaking. Requires `com.apple.security.device.audio-input` in the entitlements or
    /// the hardened runtime refuses to even PROMPT, which is unrecoverable because Microphone
    /// cannot be granted manually in System Settings the way Accessibility can (TRAP-27).
    /// `nonisolated` because it is called from the launch delegate's closure, which is not
    /// main-actor isolated. It hops to the main actor internally, so the isolation belongs on the
    /// body rather than on the entry point. Swift 6.3.3 accepted the isolated form; CI's macos-15
    /// toolchain rejected it, which is precisely why that job exists.
    private nonisolated static func requestMicrophone(for model: AppModel) {
        Task { @MainActor in
            guard !AVAudioEngineCapture.isMicrophoneAuthorized else {
                dictationLog.info("microphone already authorized")
                return
            }
            let before = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
            dictationLog.info("microphone status before=\(before) (0=undet 1=restr 2=denied 3=auth)")
            let granted = await AVAudioEngineCapture.requestMicrophoneAccess()
            let after = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
            dictationLog.info("microphone request granted=\(granted) status after=\(after)")
            if !granted {
                model.reportStartupFailure(
                    "PushText needs the Microphone to dictate. Grant it in System Settings > "
                    + "Privacy & Security > Microphone, then relaunch PushText.")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("PushText", systemImage: model.menuBarSymbol) {
            MenuContent(model: model, actions: actions)
        }
        .menuBarExtraStyle(.window)
    }
}
