import Testing
import Foundation
@testable import PushTextKit

/// Silencing the Mac while dictating (#188).
///
/// The feature is three lines; the hazard is the rest. An app that mutes the machine and is then
/// killed leaves someone's Mac silent with no visible cause, and they will not connect it to a
/// dictation utility. Every test here is about giving the sound back.
@Suite("Dictation muter")
struct DictationMuterTests {

    private final class FakeOutput: SystemAudioOutput, @unchecked Sendable {
        private let lock = NSLock()
        private var muted: Bool
        private(set) var writes: [Bool] = []
        init(muted: Bool) { self.muted = muted }
        var isMuted: Bool { lock.lock(); defer { lock.unlock() }; return muted }
        func setMuted(_ value: Bool) {
            lock.lock(); muted = value; writes.append(value); lock.unlock()
        }
    }

    /// A defaults suite of its own, so a test never writes the developer's settings (#185).
    private func store() -> UserDefaults {
        let name = "dev.ecn.apps.pushtext.test.muter.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("Dictating silences the output and giving it back restores it")
    func silenceThenRestore() {
        let output = FakeOutput(muted: false)
        let muter = DictationMuter(output: output, defaults: store())

        muter.silence()
        #expect(output.isMuted)

        muter.restore()
        #expect(output.isMuted == false)
    }

    /// Restoring to "unmuted" rather than to the PRIOR state turns someone's sound ON for them.
    /// Somebody who dictates on a deliberately silent Mac gets a surprise noise the moment they let
    /// go of the key.
    @Test("A Mac that was already silent stays silent afterwards")
    func alreadyMutedStaysMuted() {
        let output = FakeOutput(muted: true)
        let muter = DictationMuter(output: output, defaults: store())

        muter.silence()
        muter.restore()

        #expect(output.isMuted, "it was muted before dictation and must still be")
    }

    /// THE hazard. The app is killed mid-dictation, so `restore()` never runs and the Mac stays
    /// silent. The next launch has to give the sound back without being asked.
    @Test("A crash mid-dictation is repaired at the next launch")
    func crashIsRepairedOnLaunch() {
        let defaults = store()
        let crashed = FakeOutput(muted: false)
        DictationMuter(output: crashed, defaults: defaults).silence()
        #expect(crashed.isMuted, "precondition: the crash happened while muted")

        // New process, same defaults, same machine - still muted from last time.
        let next = FakeOutput(muted: true)
        DictationMuter(output: next, defaults: defaults).recoverIfInterrupted()

        #expect(next.isMuted == false, "the Mac was left silent and nothing gave the sound back")
    }

    /// Recovery must not fire when we did NOT mute. A user who muted their own Mac and then launches
    /// PushText must not have it unmuted for them.
    @Test("A clean launch never touches the volume")
    func cleanLaunchDoesNothing() {
        let output = FakeOutput(muted: true)
        DictationMuter(output: output, defaults: store()).recoverIfInterrupted()
        #expect(output.writes.isEmpty, "it changed the volume with no reason to")
        #expect(output.isMuted, "the user's own mute was overridden")
    }

    /// The ORDER, asserted directly rather than reasoned about.
    ///
    /// The intent must reach disk BEFORE the mute. Muting first leaves a window where a crash has
    /// silenced the Mac and destroyed the only evidence that we did it - recovery then never fires
    /// and the machine stays quiet forever.
    ///
    /// A plant that reversed the two lines passed every other test in this suite, because none of
    /// them dies in that window. Nothing here can kill a process mid-call, so the sequence itself is
    /// the assertion: at the moment the speaker is muted, the flag must already be on disk.
    @Test("The intent is recorded before the Mac goes quiet")
    func intentIsPersistedBeforeMuting() {
        let defaults = store()
        let key = interruptedKey
        let output = OrderedOutput(defaults: defaults, key: key)
        DictationMuter(output: output, defaults: defaults).silence()

        #expect(output.flagWhenMuted == true,
                "the Mac was muted before the reason was written down - a crash here is unrecoverable")
    }

    /// Mirrors `DictationMuter`'s own key. Duplicated deliberately: reading it from the type would
    /// make the test agree with whatever the code does, which is the tautology that let an icon
    /// assertion pass earlier today.
    private var interruptedKey: String { "dev.ecn.apps.pushtext.muter.interrupted" }

    private final class OrderedOutput: SystemAudioOutput, @unchecked Sendable {
        private let defaults: UserDefaults
        private let key: String
        private let lock = NSLock()
        private var recorded: Bool?

        init(defaults: UserDefaults, key: String) {
            self.defaults = defaults
            self.key = key
        }

        /// What the flag looked like AT THE MOMENT the speaker went quiet.
        var flagWhenMuted: Bool? { lock.lock(); defer { lock.unlock() }; return recorded }

        var isMuted: Bool { false }

        func setMuted(_ value: Bool) {
            guard value else { return }
            let seen = defaults.bool(forKey: key)
            lock.lock(); recorded = seen; lock.unlock()
        }
    }

    /// Restoring twice, or restoring without silencing, must be harmless - the model calls this from
    /// several exit paths (cancel, watchdog, failure) and they can overlap.
    @Test("Restoring more than once is harmless")
    func restoreIsIdempotent() {
        let output = FakeOutput(muted: false)
        let muter = DictationMuter(output: output, defaults: store())

        muter.restore()
        muter.silence()
        muter.restore()
        muter.restore()

        #expect(output.isMuted == false)
    }
}
