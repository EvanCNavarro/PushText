import Foundation

/// How much of a capture window actually arrived (#70, #124).
///
/// This is the ONLY guard against silent truncation. `monotonic`, `contiguous` and `dropped == 0`
/// all describe only the frames that DID arrive, so they are blind to a capture that stopped early -
/// every one of them passed on runs that lost 5 of 8 seconds to a device change. Wall time is the
/// one signal a missing frame cannot forge.
///
/// Pure, and separate from the probe that prints it, because the arithmetic had a defect that no
/// amount of running the probe would have revealed: it divided by the window the caller ASKED for.
public enum CaptureCompleteness {

    /// 15% covers ordinary start-up latency and the final partial drain. The failure this has to
    /// separate lost 66%, so the threshold is nowhere near the signal.
    public static let minimumRatio = 0.85

    /// Frames delivered, over frames the window could hold.
    ///
    /// `windowSeconds` must be the window that ACTUALLY happened, not the one requested.
    /// `RunLoop.main.run(until:)` is not bounded to its date - measured, not assumed: a 6-second
    /// block on the main run loop stretched a 3-second request to 6.219 s, and dividing the 298,496
    /// frames that arrived by the requested 3 seconds scored 2.073.
    ///
    /// That inflation is the dangerous direction. This ratio only fails LOW, so a stretched
    /// denominator does not merely make the number odd - it can carry a run that lost half its audio
    /// over the threshold. Dividing by the real window scores that same run 0.5 and fails it.
    ///
    /// A zero or negative window, or a zero sample rate, is not a measurement. Scoring it 0 fails
    /// closed, which for a truncation guard is the only safe direction.
    public static func ratio(frames: Int, sampleRate: Double, windowSeconds: Double) -> Double {
        guard windowSeconds > 0, sampleRate > 0 else { return 0 }
        return Double(frames) / (windowSeconds * sampleRate)
    }

    public static func isComplete(_ ratio: Double) -> Bool {
        ratio >= minimumRatio
    }
}
