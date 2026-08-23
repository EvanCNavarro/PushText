import Testing
import Foundation
@testable import PushTextCore

/// Distinguishes a run that owns its TCC grants from one that INHERITED them (#44).
///
/// Every hotkey proof in this repo - #3, #19-#22, and the permanent `test-packaged-app.sh` gate -
/// ran terminal-parented, where macOS attributes TCC responsibility to the terminal. The probe
/// reported `trusted=true` and the gate asserted on it, but that trust belonged to iTerm, not to
/// PushText. Launched normally the app had no grant at all, and the gate could never have noticed.
///
/// The signal is the PARENT process, and it is not a heuristic: LaunchServices reparents an app to
/// `launchd` (pid 1), while a shell-launched process keeps the shell as its parent.
@Suite("LaunchProvenance")
struct LaunchProvenanceTests {

    @Test("A launchd parent means the process owns its own TCC identity")
    func launchdParentIsSelfResponsible() {
        #expect(LaunchProvenance(parentProcessID: 1, parentName: "launchd").isSelfResponsible)
    }

    @Test("A shell parent means grants may be inherited from the shell's terminal")
    func shellParentIsInherited() {
        for shell in ["zsh", "bash", "fish", "login"] {
            let provenance = LaunchProvenance(parentProcessID: 4321, parentName: shell)
            #expect(provenance.isSelfResponsible == false, "\(shell) should read as inherited")
        }
    }

    /// The rule is about pid 1, not about the NAME being launchd - a process called "launchd" that
    /// is not pid 1 is not the system launchd, and trusting the name would be trivially spoofable.
    @Test("A non-pid-1 process merely named launchd does not count")
    func nameAloneIsNotEnough() {
        #expect(LaunchProvenance(parentProcessID: 9_000, parentName: "launchd").isSelfResponsible == false)
    }

    @Test("The description names the risk rather than only the parent")
    func descriptionIsActionable() {
        let inherited = LaunchProvenance(parentProcessID: 500, parentName: "zsh")
        #expect(inherited.description.contains("zsh"))
        #expect(inherited.description.contains("inherited"))

        let owned = LaunchProvenance(parentProcessID: 1, parentName: "launchd")
        #expect(owned.description.contains("own"))
    }

    /// Reading the REAL parent has to work, or the type is a pure function nobody calls. In a test
    /// bundle the parent is whatever ran `swift test`, so the value is not assertable - that it
    /// answers at all, with a non-empty name, is.
    @Test("The live reading answers with a real parent")
    func liveReadingWorks() {
        let live = LaunchProvenance.current()
        #expect(live.parentProcessID > 0)
        #expect(!live.parentName.isEmpty)
    }
}
