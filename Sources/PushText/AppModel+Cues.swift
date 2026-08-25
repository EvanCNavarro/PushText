import Foundation
import PushTextCore
import PushTextKit

/// The audible start and stop cues (#172).
///
/// Bobby asked for parity with the tool he compares this to, which plays a short tone when dictation
/// begins and a lower one when it ends.
extension AppModel {

    /// Plays a cue, if the user asked for cues.
    ///
    /// The preference is read PER TRANSITION rather than captured at construction, matching
    /// `cleanupEnabled`, so flipping the menu toggle takes effect on the very next dictation instead
    /// of the next launch.
    ///
    /// **Where these are called from matters more than the sound.**
    ///
    /// The start cue fires on `.recording` - the moment capture is genuinely live - and NOT on
    /// `.arming`, which is merely key-down and can still fail on a missing grant. A cue for a
    /// dictation that never started is a lie told in sound, and it is the exact failure the HUD's
    /// refusal pulse exists to avoid (#99).
    ///
    /// The stop cue fires on `.transcribing`, the moment the user stops speaking - not after
    /// injection. It marks the thing THEY did, rather than the thing the app finished doing a couple
    /// of seconds later.
    func playCue(_ tone: DictationTone) {
        guard preferences.soundEnabled else { return }
        sounds?.play(tone)
    }
}
