import Foundation

/// How channel 0 is laid out inside whatever CoreAudio just handed us (#24).
///
/// This lives in Core, away from `AVAudioSinkNode`, for one reason: the branch it decides had never
/// executed. It was written from the `AudioBufferList` contract and was reachable only from a
/// realtime callback that fires for a multi-channel interleaved input device - and every input on
/// the machine that wrote it reports 1 channel, measured rather than assumed. Waiting for hardware
/// that may never arrive is not a plan; a pure function is testable today.
public enum AudioBufferLayout {

    /// The gap, in samples, between consecutive frames of channel 0.
    ///
    /// READ from the buffer, not inferred from the format. `AudioBuffer.mNumberChannels` states how
    /// many channels are packed into THAT buffer, which is exactly the stride:
    ///
    /// - **One buffer per channel** (non-interleaved): buffer 0 holds 1 channel, so channel 0's
    ///   samples are consecutive. Striding here would read every other sample of the left channel.
    /// - **One buffer for everything** (interleaved): buffer 0 holds all N, packed
    ///   `L0 R0 L1 R1 …`, so channel 0 is every N-th sample.
    /// - **Both at once** - say 4 channels as 2 buffers of 2 - is a shape the earlier code got
    ///   WRONG. It decided on `channels == 1 || bufferCount > 1`, which reads that case as
    ///   non-interleaved and strides by 1, interleaving the two channels of buffer 0 into the ring.
    ///   The buffer's own count is right for all three.
    ///
    /// Measured before being relied on: on this machine's mono input the field is populated and
    /// agrees with the format - `bufferCount=1 bufferChannels=1 formatChannels=1`, over two probe
    /// runs. That is the only layout available here, so what is verified is that the field is FILLED
    /// IN, not that it is right for a layout no device on this machine produces.
    ///
    /// Zero is clamped rather than trapped, because this is called on the realtime audio thread: a
    /// stride below 1 would read the same sample forever, and a trap there takes the audio IO thread
    /// down with it. Clamping degrades to the mono reading, which is the harmless direction.
    public static func channelZeroStride(bufferChannels: Int) -> Int {
        max(1, bufferChannels)
    }
}
