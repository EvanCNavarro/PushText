import Testing
import Foundation
@testable import PushTextKit
import PushTextCore

/// Uninstall takes the login item with it (#162).
///
/// The backlog recorded this as a DEPENDENCY of launch-at-login rather than a nicety: an uninstall
/// that skips it leaves macOS trying to start an application that is no longer on disk, at every
/// login, with nothing left to point at.
@Suite("Login item uninstall")
@MainActor
struct LoginItemUninstallTests {

    /// NEVER `SMAppServiceLoginItem` in a test. Registering would write a real login item for the
    /// developer running the suite and leave it there.
    private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
        private let lock = NSLock()
        private var current: LoginItemState
        private(set) var disableCalls = 0
        var disableThrows = false

        init(_ state: LoginItemState) { current = state }

        var state: LoginItemState { lock.lock(); defer { lock.unlock() }; return current }
        func enable() throws { lock.lock(); current = .enabled; lock.unlock() }
        func disable() throws {
            lock.lock(); disableCalls += 1; lock.unlock()
            if disableThrows { throw CocoaError(.fileWriteUnknown) }
            lock.lock(); current = .disabled; lock.unlock()
        }
    }

    private func uninstaller(_ item: FakeLoginItem) -> Uninstaller {
        Uninstaller(library: FileManager.default.temporaryDirectory
                        .appendingPathComponent("pushtext-uninstall-\(UUID().uuidString)"),
                    repairer: NoopRepairer(),
                    loginItem: item,
                    trash: { _ in })
    }

    private final class NoopRepairer: PermissionRepairing {
        func reset(_ permissions: [Permission]) -> [PermissionRepairReport] { [] }
    }

    @Test("An enabled login item is deregistered")
    func enabledIsRemoved() {
        let item = FakeLoginItem(.enabled)
        let did = uninstaller(item).deregisterLoginItem()
        #expect(did)
        #expect(item.disableCalls == 1)
        #expect(item.state == .disabled)
    }

    /// The state that would otherwise be missed. macOS parks a registration awaiting approval, and
    /// that item is still ON the user's login list - skipping it because it is "not enabled yet"
    /// leaves exactly the orphan this exists to prevent.
    func approvalPendingIsAlsoRemoved() {
        let item = FakeLoginItem(.requiresApproval)
        #expect(uninstaller(item).deregisterLoginItem())
        #expect(item.disableCalls == 1)
    }

    @Test("Awaiting approval is deregistered too")
    func approvalPendingRemoved() { approvalPendingIsAlsoRemoved() }

    @Test("Nothing to do when it was never enabled")
    func disabledIsLeftAlone() {
        let item = FakeLoginItem(.disabled)
        #expect(uninstaller(item).deregisterLoginItem() == false)
        #expect(item.disableCalls == 0, "unregistering an item that was never registered throws")
    }

    /// An uninstall that aborts halfway because a login item would not deregister is worse than one
    /// that finishes and reports it.
    @Test("A failure is reported, not thrown")
    func failureIsReported() {
        let item = FakeLoginItem(.enabled)
        item.disableThrows = true
        #expect(uninstaller(item).deregisterLoginItem() == false)
        #expect(item.disableCalls == 1, "it must have tried")
    }
}
