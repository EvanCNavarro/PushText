import Foundation
import PushTextCore

/// Writes the start and stop cues to disk so a person can LISTEN to them (#172).
///
/// A sound is the one thing in this app that cannot be verified by reading, by a test, or by a
/// screenshot. `DictationToneTests` proves the waveform has no click, decays, and is audible - none
/// of which answers "does it sound right", which was the actual request.
///
/// It writes through the SAME `SoundFeedback.wav` and `DictationTone.samples` the app plays, so the
/// bytes judged here are the bytes shipped. A reimplementation for the probe would be judging a
/// copy.
public enum SoundProbe {

    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_SOUND_PROBE"] == "1"
    }

    public static func runAndExit() -> Never {
        let directory = ProcessInfo.processInfo.environment["PUSHTEXT_SOUND_PROBE_DIR"]
            ?? FileManager.default.temporaryDirectory.path
        let rate = 44_100.0
        for (name, tone) in [("cue-start", DictationTone.start), ("cue-stop", DictationTone.stop)] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).wav")
            let data = SoundFeedback.wav(tone.samples(sampleRate: rate), sampleRate: rate)
            do {
                try data.write(to: url)
                print("SOUND_PROBE wrote \(url.path) bytes=\(data.count) "
                    + "hz=\(Int(tone.frequency)) ms=\(Int(tone.duration * 1000))")
            } catch {
                print("SOUND_PROBE FAILED \(url.path): \(error.localizedDescription)")
                exit(1)
            }
        }
        exit(0)
    }
}
