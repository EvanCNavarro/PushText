import Foundation
import PushTextKit

/// Silencing the Mac while dictating (#188).
///
/// Called from `.recording` and from EVERY exit - the normal end, a cancel, a failure and the
/// watchdog. Restoring on only the happy path is how an app leaves someone's Mac quiet: the paths
/// that skip it are exactly the ones that fire when something has already gone wrong.
extension AppModel {

    func silenceOutputIfWanted() {
        guard preferences.silenceWhileDictating else { return }
        muter?.silence()
    }

    /// Unconditional, deliberately. It does not check the preference, because the setting can be
    /// turned OFF mid-utterance - and then the branch that would give the sound back is the branch
    /// that no longer runs. `restore()` is a no-op when nothing was silenced.
    func restoreOutput() {
        muter?.restore()
    }
}
