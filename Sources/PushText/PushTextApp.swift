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
    private let hotkey: HotkeyController
    /// Owns the Sparkle updater, so it outlives the menu being opened and closed.
    private let actions = AppActions()

    init() {
        // Headless proof of the event tap, before any UI exists. Never returns when requested.
        Self.runProbeIfRequested()
        // No probe took over, so any probe-tuning variable still set is a misconfiguration that
        // would otherwise launch the UI and look like a hung probe.
        ProbeActivation.enforceOrExit()

        // Phase 1 wiring (#12, #39): Apple's on-device SpeechAnalyzer, now that Xcode 26 ships the
        // SDK and #11 confirmed the streaming path works on this OS build. Systems that cannot run
        // it get an engine that REFUSES rather than the mock, whose canned phrases would otherwise
        // be typed into a real document — see TranscriptionEngineFactory.
        let engine = TranscriptionEngineFactory.makeDefault()
        // Plain JSONL under Application Support (#10). For an app whose pitch is that nothing
        // leaves the machine, a file the user can read with `tail` and delete with `rm` is part of
        // the claim rather than an implementation detail.
        let history = JSONLHistoryStore.defaultURL().map { JSONLHistoryStore(url: $0) }
        // The user's rewrite rules (#82). #13 measured that the engine cannot be biased, so this
        // post-pass is the only mechanism there is for proper nouns like "PushText".
        let dictionary = JSONLDictionaryStore.defaultURL().map { JSONLDictionaryStore(url: $0) }
        // Cleanup is now a USER CHOICE rather than a build-time decision (#103). The provider is
        // always constructed; `AppModel.cleanupEnabled` decides per utterance, so flipping the menu
        // toggle takes effect on the next dictation without a relaunch.
        //
        // Default OFF, and that default is #94's measurement: the key-down prewarm always completes
        // (warm=true on 12 of 12), but the model call is binary - 322 ms when its assets are
        // resident, 3494 ms when they are not, 50/50. That is a trade some users will take and
        // most will not, which is exactly what a setting is for.
        let settingsStore = UserDefaultsSettingsStore()
        let model = AppModel(engine: engine,
                             capture: AVAudioEngineCapture(),
                             injector: PasteboardTextInjector(),
                             indicator: DictationHUDController(),
                             history: history,
                             dictionary: dictionary,
                             cleanup: FoundationModelsCleanup(),
                             settingsStore: settingsStore)
        self.model = model
        // The real probe, with the persisted latch, so `grantBroken` survives a relaunch - which is
        // when the break is usually noticed, on the launch AFTER the one that worked (#6).
        model.permissionProbe = SystemPermissionProbe(latch: UserDefaultsGrantLatch())

        // Install the on-device model NOW rather than on the first key-down (#36). Detached and
        // unawaited on purpose: launch must not block on a download either, and a failure here is
        // not fatal - `beginUtterance` reports `.modelNotReady` and the user is told to wait.
        // Through the model now (#76), so progress and failure reach the menu rather than only the
        // log. Still detached: launch must not block on a download either.
        Task.detached(priority: .utility) { [model] in
            await model.prepareModel()
        }

        // The tap is the only thing that can fail at launch, and it fails for one reason worth
        // telling the user about: Accessibility is not granted. Surfaced in the menu rather than
        // thrown, because a menu-bar app that crashes on launch gives them nothing to act on.
        let controller = HotkeyController(
            binding: model.preferences.hotkeyBinding,
            onEdge: { edge in
                dictationLog.info("hotkey edge=\(String(describing: edge), privacy: .public)")
                Task { @MainActor in model.handle(edge) }
            },
            onFailure: { _ in
                model.reportStartupFailure(
                    "Hold-to-dictate needs Accessibility. Grant it in System Settings > Privacy & "
                    + "Security > Accessibility, then relaunch PushText.")
            })
        self.hotkey = controller
        controller.start()
        dictationLog.info("\(LaunchProvenance.current().description, privacy: .public)")
        // Re-point the tap when the user picks a different key. Without this the menu would show
        // the new key while the tap kept listening to the old one (#104).
        model.preferences.onHotkeyChange = { [controller] binding in
            controller.rebind(to: binding)
        }

        launchDelegate.onLaunch = { Self.requestMicrophone(for: model) }

        // Visual verification hook (#46). UI cannot be proven by a unit test - this shows the HUD
        // at a fixed level so it can be screenshotted and judged. Deliberately NOT animated: a
        // moving demo would flatter the design and hide what a real, mostly-quiet level looks like.
        Self.installHUDProbeIfRequested(on: launchDelegate)
    }

    /// Visual verification hook (#46, #115). UI cannot be proven by a unit test - this shows the HUD
    /// at a fixed level, and optionally in its REFUSED state, so both can be screenshotted.
    ///
    /// Extracted from `init` because that body hit swiftlint's 50-line limit; the probe is also a
    /// self-contained concern that has nothing to do with composing the app.
    private static func installHUDProbeIfRequested(on launchDelegate: LaunchDelegate) {
    if ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE"] == "1" {
        let level = Double(ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE_LEVEL"] ?? "") ?? 0.6
        launchDelegate.onLaunch = {
            Task { @MainActor in
                // Wait for the status item to exist: MenuBarExtra creates it after launch, and
                // anchoring before it exists is what sent the first probe to the fallback.
                try? await Task.sleep(for: .seconds(2))
                // A long hold so the PULSED state can be screenshotted (#115). The pulse
                // itself runs the same `onChange` path as production - only the hold differs -
                // so this verifies the real animation rather than a forced flag.
                let holdMs = Int(ProcessInfo.processInfo
                    .environment["PUSHTEXT_HUD_PROBE_PULSE_MS"] ?? "") ?? 150
                let hud = DictationHUDController(pulseHoldMilliseconds: holdMs)
                hud.show(phase: .recording, onCancel: {}, onConfirm: {})
                hud.update(phase: .recording, level: level)
                dictationLog.info("HUD_PROBE showing level=\(level)")
                if ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE_REFUSE"] == "1" {
                    try? await Task.sleep(for: .milliseconds(400))
                    hud.acknowledgeRefusal()
                    dictationLog.info("HUD_PROBE refused (hold \(holdMs) ms)")
                }
            }
        }
    }
    }

    /// Headless proofs of each OS-touching capability, before any UI exists. Never returns when one
    /// is requested.
    private static func runProbeIfRequested() {
        if PermissionProbeRunner.isRequested {
            PermissionProbeRunner.runAndExit()
        }
        if HotkeyProbe.isRequested {
            HotkeyProbe.runAndExit()
        }
        if AudioProbe.isRequested {
            AudioProbe.runAndExit()
        }
        if InjectionProbe.isRequested {
            InjectionProbe.runAndExit()
        }
        if TranscriptionProbe.isRequested {
            TranscriptionProbe.runAndExit()
        }
        if CleanupProbe.isRequested {
            CleanupProbe.runAndExit()
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
