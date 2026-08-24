import Foundation
import PushTextCore

/// Headless readout of the three permissions, against the REAL OS (#6).
///
/// `SystemPermissionProbeTests` drives injected closures, so it proves the derivation and nothing
/// about what `AXIsProcessTrusted()` or `CGPreflightPostEventAccess()` actually return for THIS
/// bundle. Those depend on a TCC grant keyed to the code signature, which no unit test can observe.
///
/// Activated by `PUSHTEXT_PERMISSION_PROBE=1`. Exits non-zero when anything is not granted, so it
/// is usable as a gate - but note the honest limit: run from a terminal-parented process it reports
/// the grant that was INHERITED from the terminal, not the app's own (#44).
/// Asks macOS for Accessibility trust and reports what happened (#146).
///
/// Separate from the read-only probe on purpose: this one has a SIDE EFFECT. It raises the system
/// dialog and registers this app in the Accessibility list, which is the behaviour under test - the
/// claim that prompting is what puts a row there cannot be checked by reading anything.
public enum AccessibilityTrustProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_TRUST_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        let before = AccessibilityTrust.isTrusted(prompting: false)
        print("TRUST_PROBE trustedBefore=\(before)")
        fflush(stdout)

        let after = AccessibilityTrust.isTrusted(prompting: true)
        print("TRUST_PROBE prompted=true trustedAfter=\(after)")
        // false right after prompting is NORMAL - the user has not answered yet. What the run
        // proves is whether the app now APPEARS in System Settings, which only a human can confirm.
        print("TRUST_PROBE now look in System Settings > Privacy & Security > Accessibility")
        fflush(stdout)
        exit(0)
    }
}

public enum PermissionProbeRunner {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_PERMISSION_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        // WHOSE grants these are, stated first, because it changes what every line below means.
        //
        // TCC attributes a grant to the RESPONSIBLE process, and a terminal-parented run inherits
        // the terminal's (#44). Measured: a copy of this app under a bundle id TCC has never seen
        // still reported all three granted when launched from a shell. Printing the statuses
        // without this line produces a readout that looks like proof and is not.
        let provenance = LaunchProvenance.current()
        print("PERMISSION_PROBE responsible=\(provenance.isSelfResponsible) parent=\(provenance.parentName)")
        if !provenance.isSelfResponsible {
            print("PERMISSION_PROBE WARNING grants below may be INHERITED from \(provenance.parentName), "
                  + "not this app's own")
        }
        fflush(stdout)

        // A real latch, so the readout reflects what the app would actually decide - including a
        // grantBroken it can only know from a previous run.
        let probe = SystemPermissionProbe(latch: UserDefaultsGrantLatch())
        var allGranted = true
        for permission in Permission.allCases {
            let status = probe.status(of: permission)
            if status != .granted { allGranted = false }
            print("PERMISSION_PROBE \(permission)=\(status)")
        }
        print("PERMISSION_PROBE allGranted=\(allGranted)")
        fflush(stdout)
        // A green from a non-responsible launch is not evidence, so it does not get to be exit 0.
        // Otherwise a CI gate could pass on the terminal's grants forever.
        guard provenance.isSelfResponsible else { exit(6) }
        exit(allGranted ? 0 : 5)
    }
}
