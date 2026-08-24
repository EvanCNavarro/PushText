import Testing
import Foundation
@testable import PushText
import PushTextKit

/// What the menu tells a user about a missing permission (#6).
///
/// The three-state probe exists so this copy can differ, and if it does not, the probe was pointless:
/// `needsFirstGrant` and `grantBroken` produce the SAME `AXIsProcessTrusted()` reading and need
/// opposite instructions. Telling someone to grant a permission they already granted sends them to
/// a Settings list where the app is already ticked, which reads as the app being broken.
@Suite("Permission advice")
struct PermissionAdviceTests {

    @Test("A granted permission produces no row at all")
    func grantedIsSilent() {
        for permission in Permission.allCases {
            #expect(PermissionAdvice.forStatus(.granted, of: permission) == nil,
                    "\(permission) granted should not nag")
        }
    }

    /// THE distinction the whole probe exists for.
    @Test("needsFirstGrant and grantBroken never give the same instruction")
    func theTwoStatesReadDifferently() {
        for permission in Permission.allCases {
            let first = PermissionAdvice.forStatus(.needsFirstGrant, of: permission)
            let broken = PermissionAdvice.forStatus(.grantBroken, of: permission)

            #expect(first != nil && broken != nil)
            #expect(first?.detail != broken?.detail,
                    "\(permission): identical copy makes the three-state probe pointless")
        }
    }

    /// A broken grant must not be described as a missing one. The app is already IN the list, so
    /// "allow" is an instruction the user cannot follow.
    @Test("A broken grant is described as a repair, not as a first grant")
    func brokenGrantSaysRepair() {
        for permission in Permission.allCases {
            let broken = PermissionAdvice.forStatus(.grantBroken, of: permission)
            let text = ((broken?.detail ?? "") + " " + (broken?.actionLabel ?? "")).lowercased()

            #expect(text.contains("again") || text.contains("re-") || text.contains("off and on"),
                    "\(permission) broken copy does not describe a repair: \(text)")
        }
    }

    /// PostEvent has NO pane of its own - measured, not assumed: `Privacy_PostEvent` and
    /// `Privacy_ListenEvent` do not appear in macOS 26's SecurityPrivacyExtension binary while
    /// `Privacy_Accessibility` and `Privacy_Microphone` do. So it must route to Accessibility, or
    /// the button opens nothing.
    @Test("PostEvent routes to the Accessibility pane, which is where it actually lives")
    func postEventRoutesToAccessibility() {
        let advice = PermissionAdvice.forStatus(.needsFirstGrant, of: .postEvent)
        #expect(advice?.settingsURL?.absoluteString.contains("Privacy_Accessibility") == true)
    }

    /// Uses `.denied`, not `.grantBroken`. This test asserted the BROKEN state routed to the
    /// microphone pane until 2026-08-23, which encoded the defect: a broken microphone grant is
    /// `AVAuthorizationStatus.notDetermined`, so there is no entry in that pane to act on. `.denied`
    /// is the state where a Settings trip is genuinely the answer, and it still must not land the
    /// user in the Accessibility list.
    @Test("Microphone routes to its own pane, never to Accessibility")
    func microphoneRoutesToItsOwnPane() {
        let advice = PermissionAdvice.forStatus(.denied, of: .microphone)
        #expect(advice?.settingsURL?.absoluteString.contains("Privacy_Microphone") == true)
    }

    /// The microphone's two unmet states are ONE OS state, so they must offer the same escape.
    ///
    /// `SystemPermissionProbe.microphoneStatus` derives BOTH `needsFirstGrant` and `grantBroken`
    /// from `AVAuthorizationStatus.notDetermined` - the latch is the only thing separating them, and
    /// the latch is ours, not TCC's. `requestAccess(for:)` prompts whenever the status is
    /// `.notDetermined`, so the app can ask in both cases. Sending a broken microphone grant to
    /// System Settings instead is worse than a detour: with no TCC entry recorded, there is nothing
    /// in that list to toggle.
    @Test("A broken microphone grant can still be prompted for, because it is the same OS state")
    func brokenMicrophoneStillPrompts() {
        let first = PermissionAdvice.forStatus(.needsFirstGrant, of: .microphone)
        let broken = PermissionAdvice.forStatus(.grantBroken, of: .microphone)

        #expect(first?.canPromptInApp == true)
        #expect(broken?.canPromptInApp == true,
                "same AVAuthorizationStatus.notDetermined, so the same prompt is available")
    }

    /// Accessibility and PostEvent are the opposite case, and the asymmetry is the point.
    ///
    /// They have no prompt worth raising - `AXIsProcessTrustedWithOptions` only opens Settings with
    /// less context than the row itself - so their recovery is the Settings pane in every unmet
    /// state. Asserted so a later "make it consistent" edit cannot quietly hand them a button that
    /// does nothing.
    @Test("The keyboard permissions never claim an in-app prompt")
    func keyboardPermissionsNeverPrompt() {
        for permission in [Permission.accessibility, .postEvent] {
            for status in [PermissionStatus.needsFirstGrant, .grantBroken, .denied] {
                let advice = PermissionAdvice.forStatus(status, of: permission)
                #expect(advice?.canPromptInApp == false, "\(permission)/\(status)")
                #expect(advice?.settingsURL != nil, "\(permission)/\(status) has no way out")
            }
        }
    }

    /// An explicit denial is neither a first grant nor a break, and saying "try again" to someone
    /// who deliberately said no is arguing with them.
    @Test("A denial is stated as a decision the user can revisit, not as an error")
    func denialIsItsOwnCopy() {
        let denied = PermissionAdvice.forStatus(.denied, of: .microphone)
        let broken = PermissionAdvice.forStatus(.grantBroken, of: .microphone)

        #expect(denied != nil)
        #expect(denied?.detail != broken?.detail)
    }

    /// Every row has to be actionable. A row that names a problem and offers no way out is worse
    /// than no row, because the user now knows they are stuck.
    @Test("Every non-granted state offers somewhere to go")
    func everyRowIsActionable() {
        for permission in Permission.allCases {
            for status in [PermissionStatus.needsFirstGrant, .grantBroken, .denied] {
                let advice = PermissionAdvice.forStatus(status, of: permission)
                #expect(advice?.settingsURL != nil || advice?.canPromptInApp == true,
                        "\(permission)/\(status) is a dead end")
            }
        }
    }
}
