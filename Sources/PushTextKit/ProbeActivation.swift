import Foundation

/// Catches a probe invocation whose activation variable did not survive the shell.
///
/// **The incident this exists for.** A verification run was launched as:
///
/// ```
/// PUSHTEXT_TRANSCRIBE_PROBE=1
///   PUSHTEXT_TRANSCRIBE_PROBE_SECONDS=6 "$APP/Contents/MacOS/PushText"
/// ```
///
/// The terminal wrapped the line, which split it in two. A bare `NAME=value` line is a shell
/// assignment and is NOT exported, so only `_SECONDS` reached the process. `isRequested` was false,
/// the app launched its normal menu-bar UI, and it sat in the run loop printing nothing. Everything
/// behaved correctly and the result was indistinguishable from a hung probe until someone read the
/// process's environment.
///
/// That is the same defect shape as a CI summary where zero checks and all-green render
/// identically: an absent activation must not look like a slow success.
///
/// The map is explicit rather than prefix-derived on purpose - the injection probe's companions are
/// named `PUSHTEXT_INJECT_TEXT`, not `PUSHTEXT_INJECT_PROBE_TEXT`, so a prefix rule would silently
/// cover three probes out of four while appearing to cover all of them.
public enum ProbeActivation {

    /// Every probe, with the variables that only make sense once it is activated.
    static let probes: [(activation: String, companions: [String])] = [
        ("PUSHTEXT_HOTKEY_PROBE", [
            "PUSHTEXT_HOTKEY_PROBE_SECONDS",
            "PUSHTEXT_HOTKEY_PROBE_SYNTHETIC",
            "PUSHTEXT_HOTKEY_PROBE_SECURE",
            "PUSHTEXT_HOTKEY_PROBE_STALL",
            "PUSHTEXT_HOTKEY_PROBE_TAP",
            "PUSHTEXT_HOTKEY_PROBE_KILLTAP"
        ]),
        ("PUSHTEXT_AUDIO_PROBE", [
            "PUSHTEXT_AUDIO_PROBE_SECONDS",
            "PUSHTEXT_AUDIO_PROBE_PROMPT",
            "PUSHTEXT_AUDIO_PROBE_STALL"
        ]),
        ("PUSHTEXT_INJECT_PROBE", [
            "PUSHTEXT_INJECT_TEXT",
            "PUSHTEXT_INJECT_SENTINEL",
            "PUSHTEXT_INJECT_CLIPBOARD_ONLY"
        ]),
        ("PUSHTEXT_CLEANUP_PROBE", [
            "PUSHTEXT_CLEANUP_PROBE_TEXT"
        ]),
        ("PUSHTEXT_TRUST_PROBE", []),
        ("PUSHTEXT_SOUND_PROBE", ["PUSHTEXT_SOUND_PROBE_DIR"]),
        ("PUSHTEXT_UNINSTALL_PROBE", ["PUSHTEXT_UNINSTALL_PROBE_LIBRARY"]),
        ("PUSHTEXT_MENU_PROBE", [
            "PUSHTEXT_MENU_PROBE_PERMISSION",
            "PUSHTEXT_MENU_PROBE_UPDATE",
            "PUSHTEXT_MENU_PROBE_DICTIONARY",
            "PUSHTEXT_MENU_PROBE_HISTORY",
            "PUSHTEXT_MENU_PROBE_SECONDS"
        ]),
        ("PUSHTEXT_HUD_PROBE", [
            "PUSHTEXT_HUD_PROBE_LEVEL"
        ]),
        ("PUSHTEXT_TRANSCRIBE_PROBE", [
            "PUSHTEXT_TRANSCRIBE_PROBE_SECONDS",
            "PUSHTEXT_TRANSCRIBE_PROBE_FILE",
            "PUSHTEXT_TRANSCRIBE_PROBE_REALTIME"
        ])
    ]

    /// Returns a human-readable complaint when a probe's tuning variables are set without the
    /// probe itself being activated, else nil.
    ///
    /// Takes the environment as a parameter rather than reading `ProcessInfo` so the rule is
    /// testable without mutating the test process's own environment.
    public static func misconfiguration(in environment: [String: String]) -> String? {
        for probe in probes {
            // The probes compare against "1" exactly, so "=true" activates nothing either.
            guard environment[probe.activation] != "1" else { continue }
            let present = probe.companions.filter { environment[$0] != nil }.sorted()
            guard !present.isEmpty else { continue }

            let set = present.joined(separator: ", ")
            let actual = environment[probe.activation]
                .map { "is set to \"\($0)\"" } ?? "is not set"
            return """
                \(set) \(present.count == 1 ? "is" : "are") set, but \(probe.activation) \(actual).
                The probe will NOT run and the app will launch its normal UI instead.
                A common cause is a wrapped command line: a bare `NAME=value` on its own line is a
                shell assignment and is not exported. Put the assignment on the same line as the
                command, or `export` it first.
                """
        }
        return nil
    }

    /// Complains and exits rather than launching the UI. Called from the composition root after the
    /// probe checks, so an activated probe has already taken over by this point.
    public static func enforceOrExit(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let message = misconfiguration(in: environment) else { return }
        FileHandle.standardError.write(Data("PROBE_MISCONFIGURED: \(message)\n".utf8))
        exit(78)  // EX_CONFIG
    }
}
