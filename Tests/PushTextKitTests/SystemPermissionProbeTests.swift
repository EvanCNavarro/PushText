import Testing
import Foundation
import AVFoundation
@testable import PushTextKit

/// The three-state permission model (#6).
///
/// The distinction that matters is `needsFirstGrant` versus `grantBroken`: one calls for a prompt,
/// the other for a repair, and prompting a user whose grant was invalidated by a re-sign does
/// nothing at all - the app is already in the list. `AXIsProcessTrusted()` and
/// `CGPreflightPostEventAccess()` cannot tell them apart on their own, which is what the latch is
/// for (docs/research/05 sec 7.2).
@Suite("System permission probe")
struct SystemPermissionProbeTests {

    private final class FakeLatch: PermissionGrantLatch, @unchecked Sendable {
        private let lock = NSLock()
        private var granted: Set<String> = []
        init(remembering: [Permission] = []) {
            granted = Set(remembering.map(String.init(describing:)))
        }
        func wasEverGranted(_ permission: Permission) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return granted.contains(String(describing: permission))
        }
        func recordGranted(_ permission: Permission) {
            lock.lock(); defer { lock.unlock() }
            granted.insert(String(describing: permission))
        }
        var remembered: Int { lock.lock(); defer { lock.unlock() }; return granted.count }
    }

    private func probe(
        latch: FakeLatch = FakeLatch(),
        microphone: AVAuthorizationStatus = .authorized,
        accessibility: Bool = true,
        postEvent: Bool = true
    ) -> SystemPermissionProbe {
        SystemPermissionProbe(latch: latch,
                              microphoneAuthorization: { microphone },
                              isAccessibilityTrusted: { accessibility },
                              canPostEvents: { postEvent })
    }

    @Test("A live grant reads as granted for all three")
    func liveGrants() {
        let p = probe()
        #expect(p.status(of: .microphone) == .granted)
        #expect(p.status(of: .accessibility) == .granted)
        #expect(p.status(of: .postEvent) == .granted)
    }

    /// Never asked and never granted: a prompt is the right response.
    @Test("Never granted and not granted now reads as needsFirstGrant")
    func firstGrant() {
        let p = probe(microphone: .notDetermined, accessibility: false, postEvent: false)
        #expect(p.status(of: .microphone) == .needsFirstGrant)
        #expect(p.status(of: .accessibility) == .needsFirstGrant)
        #expect(p.status(of: .postEvent) == .needsFirstGrant)
    }

    /// THE case the latch exists for. Same OS reading as above; only the memory differs.
    @Test("Granted before and not now reads as grantBroken, not needsFirstGrant")
    func brokenGrant() {
        let latch = FakeLatch(remembering: [.microphone, .accessibility, .postEvent])
        let p = probe(latch: latch, microphone: .notDetermined, accessibility: false, postEvent: false)
        #expect(p.status(of: .microphone) == .grantBroken)
        #expect(p.status(of: .accessibility) == .grantBroken)
        #expect(p.status(of: .postEvent) == .grantBroken)
    }

    /// An explicit refusal is NOT a broken grant, even if the app was trusted before. Offering to
    /// "repair" a decision the user deliberately made is the wrong response.
    @Test("An explicit denial stays denied even with a remembered grant")
    func explicitDenialIsNotBroken() {
        let latch = FakeLatch(remembering: [.microphone])
        #expect(probe(latch: latch, microphone: .denied).status(of: .microphone) == .denied)
        #expect(probe(latch: latch, microphone: .restricted).status(of: .microphone) == .denied)
    }

    /// The latch has to be WRITTEN on the way past, or it can never report a break later.
    @Test("Observing a grant records it, so a later loss is recognisable")
    func observingAGrantLatchesIt() {
        let latch = FakeLatch()
        _ = probe(latch: latch).status(of: .accessibility)

        #expect(latch.wasEverGranted(.accessibility))
        // And the memory must now change the answer for the same OS reading.
        #expect(probe(latch: latch, accessibility: false).status(of: .accessibility) == .grantBroken)
    }

    @Test("A permission that is not granted is never latched")
    func aRefusalIsNotLatched() {
        let latch = FakeLatch()
        _ = probe(latch: latch, microphone: .denied, accessibility: false, postEvent: false)
            .status(of: .accessibility)

        #expect(latch.remembered == 0)
    }

    /// Accessibility and PostEvent share one toggle in System Settings but are DISTINCT TCC
    /// services, so an app can be in the Accessibility list and still fail to post events after a
    /// re-sign (docs/research/04 sec 4). Reading one for the other would hide exactly that case.
    @Test("Accessibility and PostEvent are read independently")
    func accessibilityAndPostEventAreDistinct() {
        let p = probe(accessibility: true, postEvent: false)
        #expect(p.status(of: .accessibility) == .granted)
        #expect(p.status(of: .postEvent) == .needsFirstGrant)
    }
}
