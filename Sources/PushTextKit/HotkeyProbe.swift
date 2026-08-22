import Foundation
import CoreGraphics
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

    /// Runs the probe and exits the process. Never returns.
    public static func runAndExit() -> Never {
        let env = ProcessInfo.processInfo.environment
        let seconds = Double(env["PUSHTEXT_HOTKEY_PROBE_SECONDS"] ?? "") ?? 8

        let binding = HotkeyBinding.rightOption
        print("HOTKEY_PROBE binding=\(binding.name) keyCode=\(binding.keyCode) "
            + "deviceMask=0x\(String(binding.deviceMask, radix: 16))")
        print("HOTKEY_PROBE trusted=\(CGEventTapHotkeyMonitor.isTrusted)")

        let monitor = CGEventTapHotkeyMonitor(binding: binding)
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

        // Optional self-drive: post a bare modifier down/up through the HID event stream so the tap
        // is proven WITHOUT a human at the keyboard. This is a real CGEvent traversing the real tap
        // chain, not a direct call into the gate - the point is to prove the wiring, so short-
        // circuiting it would defeat the exercise. Off by default: it posts into the live session.
        // "1" drives the BOUND key (expect 1/1). "other" drives a DIFFERENT physical key that
        // shares the same union mask (expect 0/0) - the negative control proving side-discrimination
        // survives the real tap, not just the unit tests.
        let syntheticMode = env["PUSHTEXT_HOTKEY_PROBE_SYNTHETIC"]
        if syntheticMode == "1" || syntheticMode == "other" {
            let driven = syntheticMode == "other" ? HotkeyBinding.leftOption : binding
            print("HOTKEY_PROBE synthetic=posting driving=\(driven.name) "
                + "expect=\(driven == binding ? "1/1" : "0/0")")
            fflush(stdout)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                postSyntheticModifier(binding: driven, down: true)
                Thread.sleep(forTimeInterval: 0.08)
                postSyntheticModifier(binding: driven, down: false)
            }
        } else {
            print("HOTKEY_PROBE hold and release \(binding.name) to produce edges")
            fflush(stdout)
        }

        // Pump the real main run loop - the tap delivers through it, so a sleep would prove nothing.
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))

        monitor.stop()
        print("HOTKEY_PROBE finished pressed=\(counter.pressed) released=\(counter.released) "
            + "reEnables=\(monitor.reEnableCount)")
        fflush(stdout)
        exit(0)
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
