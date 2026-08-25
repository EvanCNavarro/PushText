import CoreAudio
import Foundation

/// The Mac's default output, as much of it as this app needs (#188).
public protocol SystemAudioOutput: Sendable {
    var isMuted: Bool { get }
    func setMuted(_ muted: Bool)
}

/// Silences the Mac while dictating, and - the part that matters - gives the sound back.
///
/// **The feature is small and the hazard is not.** An app that mutes the machine and is then killed
/// leaves someone's Mac silent with no visible cause, and nobody connects that to a dictation
/// utility. This repo already refuses to write the Globe-key SPI for exactly that reason (#176), and
/// the difference here is that WE own the restore - so it has to be durable rather than hopeful.
///
/// Three defences, and the third is the one that earns its keep:
///
/// 1. `restore()` is called from every exit, including cancel, watchdog and failure.
/// 2. It restores the PRIOR state rather than "unmuted" - somebody dictating on a deliberately
///    silent Mac must not get a surprise noise when they let go of the key.
/// 3. The intent is written to disk BEFORE the mute, so a process that dies mid-utterance is
///    repaired at the next launch by `recoverIfInterrupted()`.
public final class DictationMuter: @unchecked Sendable {

    private enum Key {
        static let interrupted = "dev.ecn.apps.pushtext.muter.interrupted"
        static let priorMuted = "dev.ecn.apps.pushtext.muter.priorMuted"
    }

    private let output: any SystemAudioOutput
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(output: any SystemAudioOutput = CoreAudioOutput(),
                defaults: UserDefaults = DefaultsSuite.current) {
        self.output = output
        self.defaults = defaults
    }

    /// Silence, remembering what to put back.
    ///
    /// The flag is written FIRST. Muting and then recording the intent leaves a window where a crash
    /// loses the only evidence that we are the reason the Mac is quiet.
    public func silence() {
        lock.lock()
        defer { lock.unlock() }
        guard !defaults.bool(forKey: Key.interrupted) else { return }
        let prior = output.isMuted
        defaults.set(true, forKey: Key.interrupted)
        defaults.set(prior, forKey: Key.priorMuted)
        output.setMuted(true)
    }

    /// Put back exactly what was there. Safe to call when nothing was silenced, because the exit
    /// paths overlap - a cancelled utterance can reach here twice.
    public func restore() {
        lock.lock()
        defer { lock.unlock() }
        guard defaults.bool(forKey: Key.interrupted) else { return }
        output.setMuted(defaults.bool(forKey: Key.priorMuted))
        defaults.removeObject(forKey: Key.interrupted)
        defaults.removeObject(forKey: Key.priorMuted)
    }

    /// Called at launch. Gives the sound back after a crash mid-dictation.
    ///
    /// Only when the flag says WE muted it - a user who silenced their own Mac and then opens
    /// PushText must not have it unmuted for them.
    public func recoverIfInterrupted() {
        restore()
    }
}

/// The real output device.
///
/// `kAudioDevicePropertyMute` on the default output. A device that does not implement mute - some
/// aggregate and virtual devices do not - reports `false` and ignores the write rather than
/// failing loudly, which is the right shape here: the worst case is that dictation is not silenced,
/// never that the Mac is left broken.
public struct CoreAudioOutput: SystemAudioOutput {

    public init() {}

    private var defaultOutputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    public var isMuted: Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = muteAddress()
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    public func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice else { return }
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }
}
