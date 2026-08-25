import SwiftUI
import MacFaceKit
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

    /// A LIST, appended to - not one closure that each caller overwrites (#170).
    ///
    /// Three call sites assign launch work: the real one, the HUD probe and the menu probe. As a
    /// single closure, last writer won, so running ANY probe silently replaced the app's real
    /// launch behaviour - the microphone request and the update check simply did not happen.
    ///
    /// That is worse than a bug in the probe, because it is a bug in the INSTRUMENT: it made the
    /// menu probe structurally incapable of observing anything that happens at launch, while still
    /// rendering a menu that looked completely normal. Found while trying to photograph the update
    /// dot coming from the real appcast and getting no dot and no log lines at all.
    private var launchHandlers: [@Sendable () -> Void] = []

    func onLaunch(_ handler: @escaping @Sendable () -> Void) {
        launchHandlers.append(handler)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for handler in launchHandlers { handler() }
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
    ///
    /// Assigned in `init()` and NOT given a default here, which is load-bearing rather than a style
    /// choice. Swift runs every stored-property default BEFORE the body of `init()` - verified by
    /// running it, not recalled - so `private let actions = AppActions()` constructed
    /// `SPUStandardUpdaterController(startingUpdater: true)` on the way past, ahead of the probe
    /// gate below. Every headless probe run therefore started Sparkle, and in a bare SPM binary with
    /// no proper bundle it failed and put up "Unable to Check For Updates ... the latest version of
    /// debug" on the user's screen. `.engine/checks/probe-gate-runs-first.sh` fails closed if a
    /// default comes back.
    private let actions: AppActions

    init() {
        // Headless proof of the event tap, before any UI exists. Never returns when requested.
        Self.runProbeIfRequested()
        // No probe took over, so any probe-tuning variable still set is a misconfiguration that
        // would otherwise launch the UI and look like a hung probe.
        ProbeActivation.enforceOrExit()

        // Only now, past the probe gate: this starts Sparkle's updater.
        actions = AppActions()

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
                // A fix-it ROW, not a sentence (#136). The tap failing is the strongest evidence
                // there is that Accessibility is unusable, so it drives the same actionable row as
                // every other missing grant instead of a dead-end string naming a Settings path.
                model.reportPermissionFailure(.accessibility)
            })
        self.hotkey = controller
        controller.start()
        dictationLog.info("\(LaunchProvenance.current().description, privacy: .public)")
        // Re-point the tap when the user picks a different key. Without this the menu would show
        // the new key while the tap kept listening to the old one (#104).
        model.preferences.onHotkeyChange = { [controller] binding in
            controller.rebind(to: binding)
        }
        // Silence the tap while the recorder waits for a key (#128). The tap is global and does not
        // care that a settings field has focus, so without this, pressing Right Option to rebind
        // would ALSO start a dictation - the user recording their own act of changing the setting.
        Self.installPermissionRetry(on: model, controller: controller)
        model.preferences.onRecordingChange = { [controller] isRecording in
            if isRecording { controller.suspend() } else { controller.resume() }
        }

        // Bound to a local first: capturing the stored property directly is a mutable capture of
        // `self` while init is still running, which Swift 6 refuses in an escaping closure.
        let launchActions = actions
        launchDelegate.onLaunch {
            Self.requestMicrophone(for: model)
            // Ask what is out there WITHOUT showing anything, so the dot can appear on its own
            // (#138). Sparkle's automatic checks stay off - this is the quiet probe, not a dialog.
            // Starts the cadence AND does the first check (#170). It used to be a single check
            // here, so the dot could only ever be right about releases that already existed when
            // the app started.
            launchActions.startUpdateChecking()
        }

        // Visual verification hook (#46). UI cannot be proven by a unit test - this shows the HUD
        // at a fixed level so it can be screenshotted and judged. Deliberately NOT animated: a
        // moving demo would flatter the design and hide what a real, mostly-quiet level looks like.
        Self.installHUDProbeIfRequested(on: launchDelegate)
        Self.installMenuProbeIfRequested(on: launchDelegate, model: model, actions: actions)
    }

    /// Lets the menu re-arm whatever the user has just granted, instead of asking for a relaunch
    /// (#152). Extracted because `init` crossed swiftlint's 50-line body limit, and because this is
    /// its own concern: what "retry" MEANS per permission is OS knowledge, not composition.
    ///
    /// Clearing a row without this would claim health the app does not have - the tap stays dead
    /// until something rebuilds it.
    private static func installPermissionRetry(on model: AppModel, controller: HotkeyController) {
        model.onRetryPermission = { permission in
            switch permission {
            case .accessibility, .postEvent: controller.start()
            case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
        }
    }

    /// Visual verification hook for the MENU (#128).
    ///
    /// The menu cannot be judged from a snapshot test: `ImageRenderer` will not rasterise an
    /// `NSViewRepresentable`, and the hotkey recorder is one - it renders as the same orange
    /// placeholder `ImageRenderer` gives an indeterminate `ProgressView`. Measured, not assumed.
    ///
    /// So the real view is hosted in an ordinary window instead, where the AppKit view draws
    /// itself properly and `screencapture -l<windowID>` can take it. This is the SAME
    /// `MenuContent` the menu bar shows, with the same model - not a mock-up of it.
    private static func installMenuProbeIfRequested(on launchDelegate: LaunchDelegate,
                                                    model: AppModel,
                                                    actions: AppActions) {
        guard ProcessInfo.processInfo.environment["PUSHTEXT_MENU_PROBE"] == "1" else { return }
        launchDelegate.onLaunch {
            Task { @MainActor in
                let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 640),
                                      styleMask: [.titled, .closable],
                                      backing: .buffered,
                                      defer: false)
                window.title = "PushText menu (probe)"
                // Force a fix-it row so it can be looked at (#136). Same idea as
                // PUSHTEXT_HUD_PROBE_REFUSE: a state that only occurs when a grant is genuinely
                // missing cannot be screenshotted on a machine where the grant is present.
                // Force an available update so the mark can be looked at - a dot that only
                // appears when a real release is newer cannot be screenshotted on demand.
                // The dictionary editor is a separate WINDOW, so it cannot be screenshotted from
                // the menu probe's own window - it has to be asked to open (#156).
                if ProcessInfo.processInfo.environment["PUSHTEXT_MENU_PROBE_DICTIONARY"] == "1" {
                    actions.editDictionary()
                }
                // The history viewer is its own window too (#161), and its three states - populated,
                // searched-to-nothing, never-recorded - look completely different. All three have to
                // be openable on demand or only the one this machine happens to be in gets looked at.
                if let mode = ProcessInfo.processInfo.environment["PUSHTEXT_MENU_PROBE_HISTORY"] {
                    actions.showHistoryProbe(mode: mode)
                }
                if ProcessInfo.processInfo.environment["PUSHTEXT_MENU_PROBE_UPDATE"] == "1" {
                    actions.updateAvailability = .available(version: "9.9.9")
                }
                if let name = ProcessInfo.processInfo.environment["PUSHTEXT_MENU_PROBE_PERMISSION"] {
                    switch name {
                    case "accessibility": model.reportPermissionFailure(.accessibility)
                    case "postEvent": model.reportPermissionFailure(.postEvent)
                    case "microphone": model.reportPermissionFailure(.microphone)
                    default: break
                    }
                }
                window.contentView = NSHostingView(rootView: MenuContent(model: model,
                                                                         actions: actions))
                window.orderFrontRegardless()
                // FORCE LAYOUT. Creating the hosting view is not enough - `MenuContent.body` is
                // only evaluated when something lays it out, and body is exactly where v0.2.0's
                // launch crash lived (#158). A probe that never evaluates body cannot catch it.
                window.contentView?.layoutSubtreeIfNeeded()
                dictationLog.info("MENU_PROBE window=\(window.windowNumber)")
                // The FRAME too, so a probe can drive a control inside this window - the overflow
                // dropdown only exists once its `...` is clicked, and `OverflowMenu` keeps `open`
                // as private @State that nothing outside can set.
                let frame = window.frame
                print("MENU_PROBE window=\(window.windowNumber) rendered=true "
                    + "frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
                    + "\(Int(frame.width)),\(Int(frame.height))")
                fflush(stdout)

                // Bounded mode for the release smoke: render, prove it, exit. Left running when
                // unset, which is what a human screenshotting it wants.
                if let seconds = Double(ProcessInfo.processInfo
                    .environment["PUSHTEXT_MENU_PROBE_SECONDS"] ?? "") {
                    try? await Task.sleep(for: .seconds(seconds))
                    print("MENU_PROBE finished")
                    fflush(stdout)
                    exit(0)
                }
            }
        }
    }

    /// Visual verification hook (#46, #115). UI cannot be proven by a unit test - this shows the HUD
    /// at a fixed level, and optionally in its REFUSED state, so both can be screenshotted.
    ///
    /// Extracted from `init` because that body hit swiftlint's 50-line limit; the probe is also a
    /// self-contained concern that has nothing to do with composing the app.
    private static func installHUDProbeIfRequested(on launchDelegate: LaunchDelegate) {
    if ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE"] == "1" {
        let level = Double(ProcessInfo.processInfo.environment["PUSHTEXT_HUD_PROBE_LEVEL"] ?? "") ?? 0.6
        launchDelegate.onLaunch {
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
        if UninstallProbe.isRequested {
            UninstallProbe.runAndExit()
        }
        if AccessibilityTrustProbe.isRequested {
            AccessibilityTrustProbe.runAndExit()
        }
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
                model.reportPermissionFailure(.microphone)
            }
        }
    }

    /// White in dark mode, black in light - the tint the menu bar would have applied itself if the
    /// badged image were still a template. Same approach as TermTile's glyph.
    private var menuBarGlyphColor: NSColor {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    var body: some Scene {
        // The icon carries the update mark too (#138), composited into ONE image rather than
        // layered: MenuBarExtra flattens and tints its label, so an overlaid badge is re-tinted to
        // the glyph colour and disappears. MacFaceKit.MenuBarBadge is that workaround, shared.
        MenuBarExtra {
            MenuContent(model: model, actions: actions)
        } label: {
            // The glyph colour is passed explicitly because a badged image is not a template, so
            // the menu bar no longer tints it - without this the symbol draws in its default black
            // and disappears on a dark menu bar. Caught by rendering it, not by any assertion.
            if let badged = MenuBarBadge.badged(systemImage: model.menuBarSymbol,
                                                attention: actions.updateAvailability
                                                    .hasAvailableUpdate,
                                                glyphColor: menuBarGlyphColor) {
                Image(nsImage: badged)
            } else {
                // A symbol that will not resolve must still leave a reachable menu.
                Image(systemName: model.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
