import Testing
import Foundation
import Synchronization
@testable import PushTextCore

/// WHAT THIS SUITE CANNOT SEE, measured rather than assumed. Four defects were planted; three were
/// caught (overwrite-on-full, an off-by-one in the wrap, a read that ignores availability - the last
/// one also tripped the 30s watchdog rather than hanging). The fourth was NOT: weakening
/// `writeIndex`'s store from `.releasing` to `.relaxed` passed all 8 tests. Memory-ordering
/// correctness here rests on the acquire/release PAIRING argument in the implementation, not on a
/// green suite, and a future edit that weakens it will not be caught by these tests.
@Suite("AudioRingBuffer")
struct AudioRingBufferTests {

    /// Writes a ramp 0,1,2,... so any reordering, tearing or off-by-one is visible in the VALUES,
    /// not just in the counts. A test that only checked counts would pass on a buffer that returns
    /// the right number of wrong samples.
    private func writeRamp(_ ring: AudioRingBuffer, from: Int, count: Int) -> Int {
        var samples = (from..<(from + count)).map { Float($0) }
        return samples.withUnsafeMutableBufferPointer { ring.write($0.baseAddress!, count: count) }
    }

    private func readAll(_ ring: AudioRingBuffer, max: Int) -> [Float] {
        var out = [Float](repeating: .nan, count: max)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: max) }
        return Array(out.prefix(n))
    }

    @Test("A write round-trips through a read, values and order intact")
    func roundTrip() {
        let ring = AudioRingBuffer(capacityFrames: 16)
        #expect(writeRamp(ring, from: 0, count: 4) == 4)
        #expect(ring.availableFrames == 4)
        #expect(readAll(ring, max: 8) == [0, 1, 2, 3])
        #expect(ring.availableFrames == 0)
    }

    @Test("Writing past capacity writes what fits and reports it, rather than growing or crashing")
    func overrunWritesWhatFits() {
        let ring = AudioRingBuffer(capacityFrames: 4)
        let written = writeRamp(ring, from: 0, count: 10)
        #expect(written == 4)
        // NOT counted as dropped by the ring: a short write only means "full". Whether those frames
        // are LOST depends on whether the caller retries, which the ring cannot know.
        #expect(ring.droppedFrames == 0)
        #expect(ring.availableFrames == 4)
        // The frames kept are the EARLIEST ones - a full ring rejects new audio, it does not
        // overwrite unread audio, which would silently corrupt a transcript.
        #expect(readAll(ring, max: 4) == [0, 1, 2, 3])
    }

    @Test("Reads and writes wrap around the end of the storage without reordering")
    func wrapAround() {
        let ring = AudioRingBuffer(capacityFrames: 8)
        #expect(writeRamp(ring, from: 0, count: 6) == 6)
        #expect(readAll(ring, max: 6) == [0, 1, 2, 3, 4, 5])
        // Now write across the physical end of the buffer.
        #expect(writeRamp(ring, from: 100, count: 7) == 7)
        #expect(readAll(ring, max: 7) == [100, 101, 102, 103, 104, 105, 106])
    }

    @Test("Reading more than is available returns only what exists")
    func readBeyondAvailable() {
        let ring = AudioRingBuffer(capacityFrames: 16)
        _ = writeRamp(ring, from: 0, count: 3)
        let got = readAll(ring, max: 99)
        #expect(got == [0, 1, 2])
        #expect(readAll(ring, max: 99).isEmpty)
    }

    @Test("Interleaved partial writes and reads preserve FIFO order")
    func interleaved() {
        let ring = AudioRingBuffer(capacityFrames: 8)
        _ = writeRamp(ring, from: 0, count: 3)
        #expect(readAll(ring, max: 2) == [0, 1])
        _ = writeRamp(ring, from: 10, count: 3)
        #expect(readAll(ring, max: 99) == [2, 10, 11, 12])
    }

    @Test("Loss is reported by the caller, not inferred from a short write")
    func callerReportsLoss() {
        let ring = AudioRingBuffer(capacityFrames: 4)
        let written = writeRamp(ring, from: 0, count: 10)
        #expect(ring.droppedFrames == 0)
        ring.recordDropped(10 - written)
        #expect(ring.droppedFrames == 6)
        ring.recordDropped(0)
        ring.recordDropped(-3)
        #expect(ring.droppedFrames == 6, "non-positive reports must be ignored, not subtracted")
    }

    @Test("reset clears content and counters")
    func resetClears() {
        let ring = AudioRingBuffer(capacityFrames: 2)
        let written = writeRamp(ring, from: 0, count: 5)
        ring.recordDropped(5 - written)
        #expect(ring.droppedFrames > 0)
        ring.reset()
        #expect(ring.availableFrames == 0)
        #expect(ring.droppedFrames == 0)
        #expect(readAll(ring, max: 4).isEmpty)
    }

    @Test("A zero or negative capacity is clamped rather than crashing")
    func capacityClamped() {
        #expect(AudioRingBuffer(capacityFrames: 0).capacityFrames >= 1)
        #expect(AudioRingBuffer(capacityFrames: -5).capacityFrames >= 1)
    }

    /// THE test this type exists for, and the one a single-threaded suite cannot express.
    ///
    /// Lock-freedom is a property that only exists DURING concurrent access: every assertion above
    /// also holds on a hopelessly racy implementation, because nothing ever races it. So this runs a
    /// real producer thread against a real consumer thread and checks two invariants a torn index
    /// would break: every frame comes back exactly once, and the ramp comes out in order.
    ///
    /// Deliberately uses `DispatchQueue`, not `Task`: the real producer is a C callback on the audio
    /// IO thread, not a Swift concurrency task, so plain threads are the faithful harness.
    @Test("Concurrent producer and consumer never tear, duplicate or reorder")
    func concurrentProducerConsumer() {
        let ring = AudioRingBuffer(capacityFrames: 512)
        let total = 200_000
        let chunk = 64

        let lock = NSLock()
        var consumed: [Float] = []
        consumed.reserveCapacity(total)
        var producerFinished = false

        let group = DispatchGroup()

        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            var next = 0
            var samples = [Float](repeating: 0, count: chunk)
            while next < total {
                let n = min(chunk, total - next)
                for i in 0..<n { samples[i] = Float(next + i) }
                let written = samples.withUnsafeMutableBufferPointer {
                    ring.write($0.baseAddress!, count: n)
                }
                next += written
            }
            lock.lock(); producerFinished = true; lock.unlock()
        }

        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            var scratch = [Float](repeating: 0, count: chunk)
            while true {
                let n = scratch.withUnsafeMutableBufferPointer {
                    ring.read(into: $0.baseAddress!, count: chunk)
                }
                if n > 0 {
                    lock.lock(); consumed.append(contentsOf: scratch.prefix(n)); lock.unlock()
                    continue
                }
                lock.lock(); let finished = producerFinished; lock.unlock()
                if finished {
                    // Final sweep so nothing written just before the flag is missed.
                    let m = scratch.withUnsafeMutableBufferPointer {
                        ring.read(into: $0.baseAddress!, count: chunk)
                    }
                    if m == 0 { break }
                    lock.lock(); consumed.append(contentsOf: scratch.prefix(m)); lock.unlock()
                }
            }
        }

        #expect(group.wait(timeout: .now() + 30) == .success, "producer/consumer did not finish")

        lock.lock(); let got = consumed; lock.unlock()
        // The producer retries on a full ring rather than giving up, and never reports loss, so the
        // counter must stay at zero. It over-counted here before loss reporting moved to the caller.
        #expect(ring.droppedFrames == 0)
        #expect(got.count == total, "expected \(total) frames, got \(got.count)")

        var expected: Float = 0
        var firstBreak: Int?
        for (i, v) in got.enumerated() {
            if v != expected { firstBreak = i; break }
            expected += 1
        }
        #expect(firstBreak == nil, "sequence broke at index \(firstBreak ?? -1)")
    }
}
