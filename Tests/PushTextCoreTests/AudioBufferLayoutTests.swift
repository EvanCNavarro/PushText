import Testing
import Foundation
@testable import PushTextCore

/// The interleaved branch of `AVAudioEngineCapture`'s sink block, made reachable (#24).
///
/// It was written from the `AudioBufferList` contract and had never run, because it was welded
/// inside a realtime callback that only fires for a multi-channel interleaved input device - and
/// every input on the machine that wrote it reports 1 channel. Waiting for that hardware is not a
/// plan; extracting the decision and the copy into pure functions is.
///
/// WHAT THIS SUITE STILL CANNOT SEE: whether CoreAudio ever hands this app an interleaved buffer at
/// all. These tests prove the logic is right FOR that layout, not that the layout occurs.
@Suite("Audio buffer layout")
struct AudioBufferLayoutTests {

    // MARK: - The decision

    /// Every layout CoreAudio can hand us, and the stride each implies.
    ///
    /// Written as ONE table rather than four tests on purpose. Reading the buffer's own channel
    /// count collapses cases that the previous inference kept apart, so `bufferChannels: 1` is the
    /// same assertion whether it came from a mono device or from buffer 0 of a non-interleaved
    /// six-channel one. Three separately-named tests asserting the identical thing would read as
    /// three independent checks and be one - which is the failure this suite exists to avoid.
    @Test("The stride is the buffer's own channel count, whatever produced it")
    func strideForEveryLayout() {
        let cases: [(String, Int, Int)] = [
            ("mono device, one buffer of one channel", 1, 1),
            ("non-interleaved 6ch: buffer 0 holds one channel", 1, 1),
            ("interleaved stereo: one buffer holds both", 2, 2),
            ("interleaved 5.1: one buffer holds all six", 6, 6),
            // The shape the OLD inference got wrong. Deciding on `channels == 1 || bufferCount > 1`
            // read 4 channels as 2 buffers of 2 as NON-interleaved and strided by 1, which would
            // have interleaved two channels into the ring as if they were one.
            ("4ch as 2 buffers of 2: interleaved WITHIN each buffer", 2, 2)
        ]
        for (name, bufferChannels, expected) in cases {
            #expect(AudioBufferLayout.channelZeroStride(bufferChannels: bufferChannels) == expected,
                    "\(name)")
        }
    }

    /// A zero channel count is not describable audio, and a stride below 1 would loop forever on one
    /// sample. Clamped rather than trapped: this runs on the realtime audio thread, where a trap
    /// takes the audio IO thread down with it.
    @Test("A nonsense channel count cannot produce a stride below one")
    func degenerateChannelCount() {
        #expect(AudioBufferLayout.channelZeroStride(bufferChannels: 0) == 1)
        #expect(AudioBufferLayout.channelZeroStride(bufferChannels: -3) == 1)
    }

    // MARK: - The copy

    /// Channel 1 carries the NEGATED frame index, so reading the wrong channel, or drifting by one
    /// sample, shows up in the VALUES. A test that only counted frames would pass on a copy that
    /// returned the right number of wrong samples.
    private func interleavedStereo(frames: Int) -> [Float] {
        var samples: [Float] = []
        for frame in 0..<frames {
            samples.append(Float(frame))
            samples.append(Float(-frame))
        }
        return samples
    }

    @Test("Interleaved stereo yields channel 0 only")
    func interleavedCopyTakesChannelZero() {
        let ring = AudioRingBuffer(capacityFrames: 64)
        var samples = interleavedStereo(frames: 8)
        let accepted = samples.withUnsafeBufferPointer {
            ring.writeChannelZero(from: $0.baseAddress!, frameCount: 8, stride: 2)
        }
        #expect(accepted == 8)
        #expect(ring.drain() == [0, 1, 2, 3, 4, 5, 6, 7])
    }

    @Test("A stride of one copies the block unchanged")
    func strideOneIsAPlainCopy() {
        let ring = AudioRingBuffer(capacityFrames: 64)
        var samples: [Float] = [1, 2, 3, 4]
        let accepted = samples.withUnsafeBufferPointer {
            ring.writeChannelZero(from: $0.baseAddress!, frameCount: 4, stride: 1)
        }
        #expect(accepted == 4)
        #expect(ring.drain() == [1, 2, 3, 4])
    }

    /// The caller reports drops, and can only do that if the short write is VISIBLE. The ring
    /// deliberately does not infer loss from a short write - see `droppedFrames`.
    @Test("A full ring accepts what it can and reports the shortfall to the caller")
    func shortWriteIsVisible() {
        let ring = AudioRingBuffer(capacityFrames: 3)
        var samples = interleavedStereo(frames: 8)
        let accepted = samples.withUnsafeBufferPointer {
            ring.writeChannelZero(from: $0.baseAddress!, frameCount: 8, stride: 2)
        }
        #expect(accepted == 3)
        #expect(ring.drain() == [0, 1, 2])
        #expect(ring.droppedFrames == 0, "the RING must not infer loss; the caller reports it")
    }

    /// Six-channel interleaved, because a stereo-only test would pass on a hardcoded stride of 2.
    @Test("A six-channel interleaved buffer still yields channel 0")
    func sixChannelInterleaved() {
        let ring = AudioRingBuffer(capacityFrames: 64)
        var samples: [Float] = []
        for frame in 0..<5 {
            samples.append(Float(frame))
            for channel in 1..<6 { samples.append(Float(100 * channel + frame)) }
        }
        let accepted = samples.withUnsafeBufferPointer {
            ring.writeChannelZero(from: $0.baseAddress!, frameCount: 5, stride: 6)
        }
        #expect(accepted == 5)
        #expect(ring.drain() == [0, 1, 2, 3, 4])
    }
}
