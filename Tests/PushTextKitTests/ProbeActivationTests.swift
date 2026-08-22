import Testing
import Foundation
@testable import PushTextKit

/// Guards the failure that cost a real verification attempt: a probe invocation whose activation
/// variable did not survive the shell, so the app launched its normal menu-bar UI and sat there.
///
/// Nothing was wrong with the app and nothing printed. The run simply outlived its window and
/// produced no output, which is indistinguishable from a slow probe until you read the process's
/// environment. That is the same shape as zero-checks-looking-like-all-green: absence must not
/// render identically to success.
@Suite("ProbeActivation")
struct ProbeActivationTests {

    @Test("A tuning variable without its activation variable is reported")
    func companionWithoutActivationIsCaught() {
        let message = ProbeActivation.misconfiguration(in: [
            "PUSHTEXT_TRANSCRIBE_PROBE_SECONDS": "6"
        ])
        #expect(message != nil)
        #expect(message?.contains("PUSHTEXT_TRANSCRIBE_PROBE") == true)
    }

    /// The exact shape that happened: a wrapped command line turned the activation assignment into
    /// a bare shell variable, so only the tuning variable was exported.
    @Test("The real incident's environment is reported")
    func theActualIncidentIsCaught() {
        let message = ProbeActivation.misconfiguration(in: [
            "PUSHTEXT_TRANSCRIBE_PROBE_SECONDS": "6",
            "HOME": "/Users/someone"
        ])
        #expect(message != nil)
    }

    @Test("A correctly activated probe is not reported")
    func activatedProbeIsFine() {
        let message = ProbeActivation.misconfiguration(in: [
            "PUSHTEXT_TRANSCRIBE_PROBE": "1",
            "PUSHTEXT_TRANSCRIBE_PROBE_SECONDS": "6"
        ])
        #expect(message == nil)
    }

    @Test("An ordinary launch with no probe variables at all is not reported")
    func ordinaryLaunchIsFine() {
        #expect(ProbeActivation.misconfiguration(in: ["HOME": "/Users/someone"]) == nil)
    }

    /// The injection probe's tuning variables do NOT share its activation prefix
    /// (PUSHTEXT_INJECT_TEXT, not PUSHTEXT_INJECT_PROBE_TEXT), so a prefix rule would silently miss
    /// them and this guard would look like it covered all four probes while covering three.
    @Test("Injection's differently-named companions are covered too")
    func injectionCompanionsAreCovered() {
        #expect(ProbeActivation.misconfiguration(in: ["PUSHTEXT_INJECT_TEXT": "hello"]) != nil)
        #expect(ProbeActivation.misconfiguration(in: ["PUSHTEXT_INJECT_CLIPBOARD_ONLY": "1"]) != nil)
        #expect(ProbeActivation.misconfiguration(in: ["PUSHTEXT_INJECT_SENTINEL": "x"]) != nil)
    }

    @Test("Every probe's companions are covered, not just the one that failed")
    func allProbesCovered() {
        for companion in ["PUSHTEXT_HOTKEY_PROBE_SECONDS",
                          "PUSHTEXT_AUDIO_PROBE_SECONDS",
                          "PUSHTEXT_INJECT_TEXT",
                          "PUSHTEXT_TRANSCRIBE_PROBE_FILE"] {
            #expect(ProbeActivation.misconfiguration(in: [companion: "x"]) != nil,
                    "\(companion) was not covered")
        }
    }

    /// An activation value other than "1" is not activation - the probes all compare against "1"
    /// exactly, so `=true` or `=yes` would launch the UI just as silently.
    @Test("An activation variable set to something other than 1 is still a misconfiguration")
    func wrongActivationValueIsCaught() {
        let message = ProbeActivation.misconfiguration(in: [
            "PUSHTEXT_AUDIO_PROBE": "true",
            "PUSHTEXT_AUDIO_PROBE_SECONDS": "4"
        ])
        #expect(message != nil)
    }
}
