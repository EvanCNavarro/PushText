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
    private let tapOptions: CGEventTapOptions
    private var gate: ModifierGate
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@Sendable (HotkeyEdge) -> Void)?
    /// Counts how many times the OS disabled our tap and we re-armed it. Surfaced because a tap that
    /// silently dies is indistinguishable from a user who stopped pressing the key.
    public private(set) var reEnableCount = 0
    /// Which disable reason last re-armed the tap, for diagnostics.
    public private(set) var lastDisableReason: CGEventType?

    /// - Parameter tapOptions: `.defaultTap` (the shipping value) can suppress events and therefore
    ///   BLOCKS event delivery while the callback runs. `.listenOnly` cannot suppress but also cannot
    ///   stall the system, which is what fault-injection uses.
    public init(binding: HotkeyBinding = .rightOption,
                tapOptions: CGEventTapOptions = .defaultTap) {
        self.binding = binding
        self.tapOptions = tapOptions
        self.gate = ModifierGate(binding: binding)
    }

    /// Fault-injection seam: sleeps this long inside the tap callback.
    ///
    /// Exists because the OS-disables-a-slow-tap branch is otherwise unreachable in a test — the OS
    /// decides when to fire it, and it never fires during normal operation. An unexecuted recovery
    /// path is indistinguishable from a working one until the day it matters. Zero in production.
    public var stallInCallback: TimeInterval = 0

    /// Whether the OS still considers our tap live.
    ///
    /// A tap can be disabled without us being told: the notification is itself an event, and events
    /// are exactly what a disabled tap stops delivering.
    public var isTapEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Fault-injection seam: disables the tap the way the OS would, without waiting for the OS.
    ///
    /// The OS-triggered disable proved uncontrollable - a 1.5s stall reached it in roughly 2 of 11
    /// runs, and a 12-event burst reached it in 0 of 5. Triggering the same real state deliberately
    /// is what makes the recovery path testable at all.
    public func forceDisableTapForTesting() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
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
            options: tapOptions,
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

    /// Re-reads the live modifier state after a tap re-arm and emits any edge the gate missed.
    ///
    /// MEASURED. When the OS disables a stalled tap it drops the events in flight, so a key release
    /// can be lost. In fault injection, every run that recovered its release was a run where the tap
    /// had been disabled and re-armed - recovery correlated with `reEnables=1` exactly.
    ///
    /// This does NOT cover the more common measured case. A stalled `.defaultTap` sits ahead of the
    /// system's own event processing, so a dropped modifier key-up leaves macOS ITSELF latched:
    /// traced runs show `CGEventSource.flagsState` still reporting the device bit set, agreeing with
    /// the stale gate. There is nothing to resynchronise against, and polling it cannot help - an
    /// earlier attempt to do exactly that was removed after 5 runs showed it changed nothing.
    /// The defence for that case is the time-based watchdog in `DictationMachine`, which depends on
    /// elapsed time rather than on any flag state.
    private func resynchronise() {
        let live = CGEventSource.flagsState(.combinedSessionState).rawValue
        if let edge = gate.update(flags: live) {
            handler?(edge)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if stallInCallback > 0 {
            Thread.sleep(forTimeInterval: stallInCallback)
        }

        // The OS disables a tap that takes too long to respond, or on certain user input. It does
        // NOT re-enable it, and it does not tell the user — the hotkey simply stops working. Re-arm.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                reEnableCount += 1
                lastDisableReason = type
                CGEvent.tapEnable(tap: tap, enable: true)
                resynchronise()
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
