import Testing
import Foundation
@testable import PushText
import PushTextKit
import PushTextCore

/// What actually happens when the user presses a fix-it button (#146).
///
/// Bobby, looking at the Accessibility pane after a Reset: *"why isn't pushtext app showing
/// automatically, there's no way of it being there now once i click the button and then to enable
/// it?"* He was right. The list contains apps that have REQUESTED the permission; PushText never
/// asked, so there was nothing to switch on - and Reset had just removed the only row that existed.
///
/// The order is the whole fix: reset the stale row, REGISTER a fresh one by prompting, then open the
/// pane. Any other order lands the user somewhere with nothing to do.
@Suite("Permission resolution")
@MainActor
struct PermissionResolutionTests {

    private final class Spy: PermissionRepairing {
        var resets: [[Permission]] = []
        var trustPrompts = 0
        var opened: [URL] = []
        var order: [String] = []

        func reset(_ permissions: [Permission]) -> [PermissionRepairReport] {
            resets.append(permissions)
            order.append("reset")
            return permissions.map { PermissionRepairReport(permission: $0, exitCode: 0) }
        }
    }

    private func actions(_ spy: Spy) -> AppActions {
        AppActions(repairer: spy,
                   requestAccessibilityTrust: { spy.trustPrompts += 1; spy.order.append("prompt") },
                   openURL: { spy.opened.append($0); spy.order.append("open") })
    }

    /// THE bug. Resetting without registering leaves the pane empty.
    @Test("A broken keyboard grant resets, then REGISTERS, then opens Settings")
    func brokenGrantRegistersBeforeOpening() {
        let spy = Spy()
        let advice = try! #require(PermissionAdvice.forStatus(.grantBroken, of: .accessibility))
        actions(spy).resolvePermission(advice)

        #expect(spy.order == ["reset", "prompt", "open"],
                "got \(spy.order) - the pane must not open before the app is registered")
        #expect(spy.resets == [[.accessibility]])
    }

    /// A first grant has no stale row to clear, but still needs registering or the list stays empty.
    @Test("A first keyboard grant registers even though there is nothing to reset")
    func firstGrantStillRegisters() {
        let spy = Spy()
        let advice = try! #require(PermissionAdvice.forStatus(.needsFirstGrant, of: .accessibility))
        actions(spy).resolvePermission(advice)

        #expect(spy.resets.isEmpty, "nothing to reset on a first grant")
        #expect(spy.trustPrompts == 1, "without this the Accessibility list has no PushText row")
        #expect(spy.order == ["prompt", "open"])
    }

    /// PostEvent shares the Accessibility pane and the same registration path.
    @Test("Input control registers too")
    func postEventRegisters() {
        let spy = Spy()
        let advice = try! #require(PermissionAdvice.forStatus(.grantBroken, of: .postEvent))
        actions(spy).resolvePermission(advice)
        #expect(spy.trustPrompts == 1)
    }

    /// The microphone must NOT take this path: it has its own prompt, and asking for Accessibility
    /// trust because the mic is missing would put a dialog in front of the wrong question.
    @Test("The microphone prompts for itself and never asks for Accessibility trust")
    func microphoneDoesNotAskForAccessibility() {
        let spy = Spy()
        let advice = try! #require(PermissionAdvice.forStatus(.needsFirstGrant, of: .microphone))
        actions(spy).resolvePermission(advice)

        #expect(spy.trustPrompts == 0)
        #expect(spy.resets.isEmpty)
        #expect(spy.opened.isEmpty, "the mic prompt is in-app; no pane should open")
    }

    /// A denial is a decision. Registering again would re-ask a question the user already answered.
    @Test("A denied keyboard grant opens Settings without resetting or re-asking")
    func denialJustOpensSettings() {
        let spy = Spy()
        let advice = try! #require(PermissionAdvice.forStatus(.denied, of: .accessibility))
        actions(spy).resolvePermission(advice)

        #expect(spy.resets.isEmpty)
        #expect(spy.trustPrompts == 0)
        #expect(spy.order == ["open"])
    }
}
