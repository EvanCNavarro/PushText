import Foundation
import CoreGraphics
import ApplicationServices
import PushTextCore

/// Watches a bound modifier key system-wide with a `CGEvent` tap on `.flagsChanged`.
///
/// Why a tap rather than the alternatives, all of which were evaluated in docs/research/04 sec 1:
///
/// - `NSEvent.addGlobalMonitorForEvents` is observe-only by Apple's own documentation, so it can
///   never suppress the keystroke if we later need to.
/// - Carbon's `RegisterEventHotKey` cannot express a BARE modifier at all, and its header states
///   right-side modifiers are "Not supported on Mac OS X".
///
/// A tap on `.flagsChanged` also survives Secure Input: secure input filters `keyDown`/`keyUp` but
/// lets `flagsChanged` through, so a bare-modifier binding keeps working in password fields where a
/// chord would silently stop firing.
///
/// The tap is created as `.defaultTap` rather than `.listenOnly` — it passes every event through
/// untouched today, but `.listenOnly` cannot ever suppress, and changing tap type later means
/// re-granting nothing but rewriting this class. Passing events through is deliberate: swallowing
/// `flagsChanged` for Option would break every Option-key shortcut and dead-key on the system.
public final class CGEventTapHotkeyMonitor: HotkeyMonitor, @unchecked Sendable {

    public enum MonitorError: Error, Equatable {
        /// `AXIsProcessTrusted()` is false. The tap would be created and then never fire.
        case accessibilityNotTrusted
        /// The OS refused the tap even though we appear trusted.
        case tapCreationFailed
    }

    private let binding: HotkeyBinding
    private var gate: ModifierGate
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@Sendable (HotkeyEdge) -> Void)?
    /// Counts how many times the OS disabled our tap and we re-armed it. Surfaced because a tap that
    /// silently dies is indistinguishable from a user who stopped pressing the key.
    public private(set) var reEnableCount = 0

    public init(binding: HotkeyBinding = .rightOption) {
        self.binding = binding
        self.gate = ModifierGate(binding: binding)
    }

    /// Whether this process may create a functioning event tap.
    ///
    /// Checked WITHOUT prompting — `AXIsProcessTrustedWithOptions` with the prompt option shows a
    /// system dialog, which is the caller's decision to make, not this method's.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func start(onEvent: @escaping @Sendable (HotkeyEdge) -> Void) throws {
        // Creating a tap while untrusted SUCCEEDS and then never delivers an event, which reads
        // exactly like a broken hotkey. Fail loudly instead.
        guard Self.isTrusted else { throw MonitorError.accessibilityNotTrusted }

        handler = onEvent
        gate = ModifierGate(binding: binding)

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        // The C callback cannot capture, so `self` travels through userInfo unretained. `stop()`
        // tears the tap down before deinit, so the pointer cannot outlive the object.
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CGEventTapHotkeyMonitor>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            handler = nil
            throw MonitorError.tapCreationFailed
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        handler = nil
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The OS disables a tap that takes too long to respond, or on certain user input. It does
        // NOT re-enable it, and it does not tell the user — the hotkey simply stops working. Re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                reEnableCount += 1
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged, let edge = gate.update(flags: event.flags.rawValue) {
            handler?(edge)
        }

        // Always pass the event through untouched. See the class comment.
        return Unmanaged.passUnretained(event)
    }
}
