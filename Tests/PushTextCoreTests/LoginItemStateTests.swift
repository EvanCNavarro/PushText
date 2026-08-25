import Testing
@testable import PushTextCore

/// The three states a login item can be in (#162).
@Suite("Login item state")
struct LoginItemStateTests {

    @Test("Enabled reads as on and needs nothing")
    func enabledIsOn() {
        #expect(LoginItemState.enabled.isOn)
        #expect(LoginItemState.enabled.needsUserApproval == false)
    }

    @Test("Disabled reads as off")
    func disabledIsOff() {
        #expect(LoginItemState.disabled.isOn == false)
        #expect(LoginItemState.disabled.needsUserApproval == false)
    }

    /// The state that makes a Bool lie. macOS can accept the registration and still park the item
    /// awaiting approval in System Settings - the app will NOT start at the next login. Drawing that
    /// as OFF would invite the user to toggle it again, which does nothing; drawing it as ON with no
    /// explanation is the silent version of the same lie.
    @Test("Awaiting approval reads as on, and says it needs the user")
    func approvalIsOnButFlagged() {
        #expect(LoginItemState.requiresApproval.isOn,
                "the user asked for it - the switch reflects their intent")
        #expect(LoginItemState.requiresApproval.needsUserApproval,
                "nothing would explain why the app did not start at login")
    }
}
