import Foundation

/// When the passive update probe may run again (#170).
///
/// The dot used to be right only about releases that already existed when the app STARTED: the
/// probe ran once from `onLaunch` and nothing ever re-ran it. `SUEnableAutomaticChecks` is false and
/// stays false - automatic checks make Sparkle present its own dialog on a schedule, and a dictation
/// utility that opens a window unprompted is not what was promised - so the re-checking has to be
/// ours, and it has to stay silent.
///
/// Pure, and in Core, because "may I check now" is a decision with right and wrong answers and none
/// of them need a network or a clock we do not control.
public enum UpdateCheckPolicy {

    /// The floor between checks. The menu asks on every open and the menu is opened constantly;
    /// without this the app would hit the appcast every time the user glanced at it.
    public static let quietPeriod: TimeInterval = 30 * 60

    /// The unattended cadence, for the icon in the menu bar - the one mark that is visible without
    /// the user doing anything at all.
    public static let background: TimeInterval = 6 * 3600

    public static func shouldCheck(lastCompleted: Date?,
                                   now: Date,
                                   isChecking: Bool,
                                   quietPeriod: TimeInterval = UpdateCheckPolicy.quietPeriod) -> Bool {
        // A second probe on top of a live one is how availability gets stranded on `.checking`,
        // which renders as no dot at all.
        guard !isChecking else { return false }
        guard let lastCompleted else { return true }
        let elapsed = now.timeIntervalSince(lastCompleted)
        // NEGATIVE means the clock moved backwards - a timezone change, an NTP correction, a laptop
        // waking with a bad RTC. Reading that as "just checked" would disable the probe until real
        // time caught up, which on a large correction is indistinguishable from forever.
        guard elapsed >= 0 else { return true }
        return elapsed >= quietPeriod
    }
}
