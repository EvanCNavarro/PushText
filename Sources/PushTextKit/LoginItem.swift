import Foundation
import PushTextCore
import ServiceManagement

/// Starting PushText at login (#162).
///
/// A protocol so nothing else has to touch `SMAppService`, and - more importantly - so no TEST ever
/// does. `SMAppService.mainApp.register()` writes a REAL login item for the running user; a test
/// that called it would change the developer's machine and leave it changed. That is not
/// hypothetical: earlier the same day, an instrumented probe in this repo persisted a synthetic key
/// capture into the real preferences and silently changed Bobby's dictation hotkey.
public protocol LoginItemControlling: Sendable {
    var state: LoginItemState { get }
    func enable() throws
    func disable() throws
}

/// The real thing, backed by `SMAppService.mainApp`.
///
/// `mainApp` rather than a helper bundle: PushText IS the thing to launch, there is no separate
/// login helper to install, and `SMAppService` handles the registration that `LSSharedFileList`
/// used to do badly.
public struct SMAppServiceLoginItem: LoginItemControlling {

    public init() {}

    public var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            // Registered, and parked until the user approves it in System Settings. The app will
            // NOT start at the next login while it sits here.
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            // A state this macOS knows and we do not. Reporting `disabled` is the honest default:
            // it never claims the app will start when it might not.
            return .disabled
        }
    }

    public func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Unregistering an item that was never registered throws, and that is not a failure worth
    /// surfacing - uninstall calls this unconditionally, and "it was already off" is the expected
    /// case rather than an error.
    public func disable() throws {
        guard SMAppService.mainApp.status != .notRegistered else { return }
        try SMAppService.mainApp.unregister()
    }
}
