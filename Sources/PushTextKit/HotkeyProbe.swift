import Foundation
import CoreGraphics
import Carbon
import PushTextCore

/// Headless proof that the event tap is real.
///
/// A green unit suite proves `ModifierGate`'s arithmetic and nothing about whether macOS will
/// actually hand this process key events — that depends on a TCC grant, on the tap surviving
/// creation, and on the run loop being pumped. This runs the real path and prints machine-readable
/// markers so `scripts/test-packaged-app.sh` can assert on them later.
///
/// Activated by `PUSHTEXT_HOTKEY_PROBE=1`. `PUSHTEXT_HOTKEY_PROBE_SECONDS` bounds the run
/// (default 8). Exits non-zero when the tap could not be created, so it is usable as a gate.
public enum HotkeyProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_HOTKEY_PROBE"] == "1"
    }

    /// The binding named by `PUSHTEXT_HOTKEY_PROBE_KEY`, or Right Option.
    ///
    /// Selectable because the claim that mattered was about a DIFFERENT key: Globe was refused for
    /// months on a comment saying a tap cannot see it (#176), and this is how that was proven on
    /// real hardware rather than argued from a research document.
    private static func requestedBinding(_ requested: String?) -> HotkeyBinding {
        let wanted = requested?.lowercased()
        return HotkeyBinding.selectable.first {
            $0.name.lowercased().replacingOccurrences(of: " ", with: "") == wanted
                || ($0 == .globe && (wanted == "globe" || wanted == "fn"))
        } ?? HotkeyBinding.rightOption
    }

    /// Runs the probe and exits the process. Never returns.
    public static func runAndExit() -> Never {
        let env = ProcessInfo.processInfo.environment
        let seconds = Double(env["PUSHTEXT_HOTKEY_PROBE_SECONDS"] ?? "") ?? 8
        // Selectable, because the claim that matters now is about a DIFFERENT key. Globe was
        // refused for months on a comment saying a tap cannot see it (#176); the tap can, and this
        // is how that gets proven on real hardware rather than argued from a research document.
        //   PUSHTEXT_HOTKEY_PROBE=1 PUSHTEXT_HOTKEY_PROBE_KEY=globe <app-binary>
        let binding = requestedBinding(env["PUSHTEXT_HOTKEY_PROBE_KEY"])

        print("HOTKEY_PROBE binding=\(binding.name) keyCode=\(binding.keyCode) "
            + "deviceMask=0x\(String(binding.deviceMask, radix: 16))")
        // Report HOW we were launched alongside trust. A terminal-parented run inherits the
        // terminal's Accessibility grant, so `trusted=true` there says nothing about the app's own
        // identity - and a green from an inherited grant is byte-identical to a real one (#44).
        let provenance = LaunchProvenance.current()
        print("HOTKEY_PROBE trusted=\(CGEventTapHotkeyMonitor.isTrusted) "
            + "selfResponsible=\(provenance.isSelfResponsible) "
            + "parent=\(provenance.parentName)(\(provenance.parentProcessID))")

        let monitor = makeMonitor(binding: binding, env: env)
        let counter = EdgeCounter()

        do {
            try monitor.start { edge in
                counter.record(edge)
                print("HOTKEY_PROBE edge=\(edge == .pressed ? "pressed" : "released")")
                fflush(stdout)
            }
        } catch {
            print("HOTKEY_PROBE tap=failed error=\(error)")
            fflush(stdout)
            exit(1)
        }

        print("HOTKEY_PROBE tap=armed seconds=\(seconds)")
        fflush(stdout)

        // #22: kill the tap the way the OS would, and see whether the monitor notices.
        if env["PUSHTEXT_HOTKEY_PROBE_KILLTAP"] == "1" {
            print("HOTKEY_PROBE killtap=before enabled=\(monitor.isTapEnabled)")
            monitor.forceDisableTapForTesting()
            print("HOTKEY_PROBE killtap=killed enabled=\(monitor.isTapEnabled)")
            fflush(stdout)
            RunLoop.main.run(until: Date().addingTimeInterval(3.0))
            let reason = monitor.lastDisableReason.map { String($0.rawValue) } ?? "none"
            print("HOTKEY_PROBE killtap=after enabled=\(monitor.isTapEnabled) "
                + "reEnables=\(monitor.reEnableCount) reason=\(reason)")
            fflush(stdout)
        }

        if env["PUSHTEXT_HOTKEY_PROBE_SECURE"] == "1" {
            runSecureInputExperiment(binding: binding, counter: counter)
        } else {
            driveOrWait(binding: binding, env: env)
            // Pump the REAL main run loop - the tap delivers through it, so a sleep proves nothing.
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        monitor.stop()
        print("HOTKEY_PROBE finished consumed=\(monitor.consumedCount) "
            + "pressed=\(counter.pressed) released=\(counter.released) "
            + "reEnables=\(monitor.reEnableCount)")
        fflush(stdout)
        exit(0)
    }

    /// Builds the monitor, applying the fault-injection stall when one is configured.
    ///
    /// A stalled LISTEN-ONLY tap is never disabled by the OS - nothing waits on it, so there is no
    /// timeout to breach (measured: a 2.0s stall gave reEnables=0). Reaching the re-arm branch needs
    /// a `.defaultTap`, which DOES hold up event delivery while the callback runs. Default to the
    /// safe one and require `PUSHTEXT_HOTKEY_PROBE_TAP=default` to opt into the disruptive one.
    private static func makeMonitor(
        binding: HotkeyBinding,
        env: [String: String]
    ) -> CGEventTapHotkeyMonitor {
        let stall = Double(env["PUSHTEXT_HOTKEY_PROBE_STALL"] ?? "") ?? 0
        let wantsDefaultTap = (env["PUSHTEXT_HOTKEY_PROBE_TAP"] ?? "") == "default"
        let options: CGEventTapOptions = (stall > 0 && !wantsDefaultTap) ? .listenOnly : .defaultTap
        let monitor = CGEventTapHotkeyMonitor(binding: binding, tapOptions: options)
        monitor.stallInCallback = stall
        if stall > 0 {
            print("HOTKEY_PROBE stall=\(stall) "
                + "tapOptions=\(options == .listenOnly ? "listenOnly" : "defaultTap")")
        }
        return monitor
    }

    /// Enables Secure Input, drives the bound key, and reports whether edges still arrived.
    ///
    /// docs/research/04 sec 1 claims `flagsChanged` keeps flowing under Secure Input while
    /// `keyDown`/`keyUp` do not - the strongest argument for binding a BARE MODIFIER over a chord.
    ///
    /// The control matters more than the result: if `IsSecureEventInputEnabled()` were false the run
    /// would prove nothing, so it is asserted and printed rather than assumed.
    private static func runSecureInputExperiment(binding: HotkeyBinding, counter: EdgeCounter) {
        print("HOTKEY_PROBE secure=before enabled=\(IsSecureEventInputEnabled())")
        let status = EnableSecureEventInput()
        defer {
            _ = DisableSecureEventInput()
            print("HOTKEY_PROBE secure=after enabled=\(IsSecureEventInputEnabled())")
            fflush(stdout)
        }
        print("HOTKEY_PROBE secure=enabled status=\(status) "
            + "confirmed=\(IsSecureEventInputEnabled())")
        fflush(stdout)

        postSyntheticModifier(binding: binding, down: true)
        Thread.sleep(forTimeInterval: 0.10)
        postSyntheticModifier(binding: binding, down: false)
        // Pump the run loop so the callback can fire BEFORE Secure Input is torn down.
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        print("HOTKEY_PROBE secure=result pressed=\(counter.pressed) "
            + "released=\(counter.released)")
        fflush(stdout)
    }

    /// Optionally self-drives the tap, otherwise waits for a human.
    ///
    /// The synthetic events are real `CGEvent`s traversing the real tap chain, not direct calls into
    /// the gate - short-circuiting that would defeat the exercise. `"1"` drives the BOUND key
    /// (expect 1/1); `"other"` drives a different physical key sharing the same union mask
    /// (expect 0/0), the negative control for side-discrimination.
    private static func driveOrWait(binding: HotkeyBinding, env: [String: String]) {
        let mode = env["PUSHTEXT_HOTKEY_PROBE_SYNTHETIC"]
        guard mode == "1" || mode == "other" else {
            print("HOTKEY_PROBE hold and release \(binding.name) to produce edges")
            fflush(stdout)
            return
        }
        let driven = mode == "other" ? HotkeyBinding.leftOption : binding
        print("HOTKEY_PROBE synthetic=posting driving=\(driven.name) "
            + "expect=\(driven == binding ? "1/1" : "0/0")")
        fflush(stdout)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            postSyntheticModifier(binding: driven, down: true)
            Thread.sleep(forTimeInterval: 0.08)
            postSyntheticModifier(binding: driven, down: false)
        }
    }
}

/// Posts a bare modifier key event carrying the binding's device-dependent bit.
///
/// `flagsChanged` events are synthesised as a keyDown/keyUp on the modifier's virtual keycode with
/// the flags set explicitly - a modifier has no separate event type of its own.
private func postSyntheticModifier(binding: HotkeyBinding, down: Bool) {
    guard let event = CGEvent(
        keyboardEventSource: CGEventSource(stateID: .hidSystemState),
        virtualKey: CGKeyCode(binding.keyCode),
        keyDown: down
    ) else { return }
    event.type = .flagsChanged
    // NX_ALTERNATEMASK-style union bit is what the OS would also set; include the device bit, which
    // is the part the gate actually reads.
    event.flags = down ? CGEventFlags(rawValue: binding.deviceMask | 0x0008_0000) : []
    event.post(tap: .cghidEventTap)
}

/// Tallies edges across the callback boundary.
private final class EdgeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var pressedCount = 0
    private var releasedCount = 0

    var pressed: Int { lock.withLock { pressedCount } }
    var released: Int { lock.withLock { releasedCount } }

    func record(_ edge: HotkeyEdge) {
        lock.withLock {
            switch edge {
            case .pressed: pressedCount += 1
            case .released: releasedCount += 1
            }
        }
    }
}
