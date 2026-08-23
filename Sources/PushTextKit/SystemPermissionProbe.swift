import Foundation
import AVFoundation
import ApplicationServices
import CoreGraphics

/// Remembers that a permission was once granted.
///
/// This is the whole reason a three-state answer is possible. `AXIsProcessTrusted()` and
/// `CGPreflightPostEventAccess()` return a Bool: "not trusted" covers both "never asked" and "was
/// working and is now broken", which need OPPOSITE responses - prompt versus repair. Only a
/// persisted memory of a previous grant separates them (docs/research/05 sec 7.2).
public protocol PermissionGrantLatch: Sendable {
    func wasEverGranted(_ permission: Permission) -> Bool
    func recordGranted(_ permission: Permission)
}

/// Non-prompting status for the three permissions this app needs.
public struct SystemPermissionProbe: PermissionProbe {

    private let latch: any PermissionGrantLatch
    private let microphoneAuthorization: @Sendable () -> AVAuthorizationStatus
    private let isAccessibilityTrusted: @Sendable () -> Bool
    private let canPostEvents: @Sendable () -> Bool

    public init(
        latch: any PermissionGrantLatch,
        microphoneAuthorization: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        canPostEvents: @escaping @Sendable () -> Bool = { CGPreflightPostEventAccess() }
    ) {
        self.latch = latch
        self.microphoneAuthorization = microphoneAuthorization
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.canPostEvents = canPostEvents
    }

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return microphoneStatus()
        case .accessibility:
            return derive(isGranted: isAccessibilityTrusted(), for: .accessibility)
        case .postEvent:
            return derive(isGranted: canPostEvents(), for: .postEvent)
        }
    }

    /// Microphone is the one permission with a real four-state API, so an explicit refusal is
    /// distinguishable from silence.
    ///
    /// `.denied` is NOT routed through the latch. A user who said no made a decision, and offering
    /// to "repair" it would be arguing with them; only `.notDetermined` is ambiguous between never
    /// asked and a grant invalidated by a re-sign.
    private func microphoneStatus() -> PermissionStatus {
        switch microphoneAuthorization() {
        case .authorized:
            latch.recordGranted(.microphone)
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return latch.wasEverGranted(.microphone) ? .grantBroken : .needsFirstGrant
        @unknown default:
            // A case Apple adds later must not read as granted. Treating the unknown as "ask" is
            // the harmless direction: a prompt the user does not need beats silently believing we
            // have access we do not.
            return .needsFirstGrant
        }
    }

    /// The Bool permissions. Latching on the way past is what makes a later loss legible.
    private func derive(isGranted: Bool, for permission: Permission) -> PermissionStatus {
        guard !isGranted else {
            latch.recordGranted(permission)
            return .granted
        }
        return latch.wasEverGranted(permission) ? .grantBroken : .needsFirstGrant
    }
}

/// The latch, persisted so it survives relaunch - which is the whole point, since the break it
/// detects is usually noticed on the launch AFTER the one that worked.
public struct UserDefaultsGrantLatch: PermissionGrantLatch {

    /// `UserDefaults` is not `Sendable`, but it IS documented thread-safe, so the unchecked box is
    /// the accurate description rather than a shortcut: the compiler cannot see a guarantee the
    /// class makes in prose.
    private let defaults: UncheckedBox<UserDefaults>

    public init(defaults: UserDefaults = .standard) {
        self.defaults = UncheckedBox(defaults)
    }

    /// Namespaced so it cannot collide with anything else in the domain.
    private func key(_ permission: Permission) -> String {
        "dev.ecn.apps.pushtext.grantLatch.\(permission)"
    }

    public func wasEverGranted(_ permission: Permission) -> Bool {
        defaults.value.bool(forKey: key(permission))
    }

    public func recordGranted(_ permission: Permission) {
        // Written only on a transition, not on every poll: `status` is called from UI refreshes and
        // an unconditional write would hit the defaults database several times a second.
        guard !defaults.value.bool(forKey: key(permission)) else { return }
        defaults.value.set(true, forKey: key(permission))
    }
}

/// Carries a documented-thread-safe reference class across a `Sendable` boundary.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
