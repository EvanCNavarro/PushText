import AppKit
import AVFoundation
import SwiftUI
import PushTextKit

/// The launch-time probes, kept out of `PushTextApp` so the app file describes the APP.
///
/// Split out when that file reached its 400-line limit during #209: the harness had grown to about
/// a third of it, and the thing being read most often is not the harness.
extension PushTextApp {

    /// Visual verification hook for the MENU (#128).
    ///
    /// The menu cannot be judged from a snapshot test: `ImageRenderer` will not rasterise an
    /// `NSViewRepresentable`, and the hotkey recorder is one - it renders as the same orange
    /// placeholder `ImageRenderer` gives an indeterminate `ProgressView`. Measured, not assumed.
    ///
    /// So the real view is hosted in an ordinary window instead, where the AppKit view draws
    /// itself properly and `screencapture -l<windowID>` can take it. This is the SAME
    /// `MenuContent` the menu bar shows, with the same model - not a mock-up of it.
    static func installMenuProbeIfRequested(on launchDelegate: LaunchDelegate,
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
    static func installHUDProbeIfRequested(on launchDelegate: LaunchDelegate) {
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
    static func runProbeIfRequested() {
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
        if SoundProbe.isRequested {
            SoundProbe.runAndExit()
        }
    }
}
