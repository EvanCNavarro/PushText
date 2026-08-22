import Foundation
import Synchronization

/// A fixed-capacity, lock-free, single-producer/single-consumer FIFO for audio frames.
///
/// This exists because of one line in `AVAudioSinkNode.h`: the receiver block
/// *"will be called on the realtime thread and it is the client's responsibility to handle it in a
/// thread-safe manner and to **not make any blocking calls**."*
///
/// A lock is a blocking call. So is `malloc`, which is what appending to a Swift `Array` can do. The
/// producer side here allocates nothing and locks nothing: storage is reserved once at init, and the
/// two indices are plain atomics. Overrun is handled by DROPPING and counting, never by growing —
/// a dictation app would rather lose audio it can report than stall the audio IO thread.
///
/// Single producer, single consumer. Two writers race; that is out of contract, not a bug here.
public final class AudioRingBuffer: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    /// Total frames ever written. Producer-owned; consumer only reads it.
    private let writeIndex = Atomic<Int>(0)
    /// Total frames ever read. Consumer-owned; producer only reads it.
    private let readIndex = Atomic<Int>(0)
    private let dropped = Atomic<Int>(0)

    /// - Parameter capacityFrames: ring size in frames. Clamped to at least 1.
    public init(capacityFrames: Int) {
        capacity = max(1, capacityFrames)
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    public var capacityFrames: Int { capacity }

    /// Frames written but not yet read.
    public var availableFrames: Int {
        writeIndex.load(ordering: .acquiring) - readIndex.load(ordering: .acquiring)
    }

    /// Frames the CALLER reported as lost, via `recordDropped(_:)`.
    ///
    /// The ring deliberately does not infer this from a short write. A short write means "the ring
    /// was full", which is only a LOSS if the caller cannot retry — true on the audio thread, false
    /// for a producer that loops. Inferring it here over-counted by 320 frames in a retrying test
    /// and made a correct run look lossy.
    public var droppedFrames: Int {
        dropped.load(ordering: .acquiring)
    }

    /// Records frames the caller could not hand over and will not retry.
    public func recordDropped(_ frames: Int) {
        guard frames > 0 else { return }
        dropped.add(frames, ordering: .relaxed)
    }

    /// Producer side. Realtime-safe: no allocation, no locks.
    /// - Returns: frames actually written. Less than `count` means the ring was full.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        // Indices are monotonic totals, never wrapped, so `write - read` is unambiguous even as
        // they run away - wrapping only happens when indexing storage.
        let write = writeIndex.load(ordering: .relaxed)          // producer owns it; relaxed is fine
        let read = readIndex.load(ordering: .acquiring)          // pairs with the consumer's release
        let free = capacity - (write - read)
        let toWrite = min(count, free)

        // A full ring REJECTS new audio rather than overwriting unread audio: a rejected tail is
        // countable by whoever knows whether it can be retried; a silently overwritten middle
        // corrupts the transcript with no trace.
        guard toWrite > 0 else { return 0 }

        let offset = write % capacity
        let firstChunk = min(toWrite, capacity - offset)
        storage.advanced(by: offset).update(from: source, count: firstChunk)
        if firstChunk < toWrite {
            storage.update(from: source.advanced(by: firstChunk), count: toWrite - firstChunk)
        }

        // Release: the copy above must be visible before the consumer can see the new index.
        writeIndex.store(write + toWrite, ordering: .releasing)
        return toWrite
    }

    /// Consumer side.
    /// - Returns: frames actually read, up to `count`.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let read = readIndex.load(ordering: .relaxed)            // consumer owns it
        let write = writeIndex.load(ordering: .acquiring)        // pairs with the producer's release
        let toRead = min(count, write - read)
        guard toRead > 0 else { return 0 }

        let offset = read % capacity
        let firstChunk = min(toRead, capacity - offset)
        destination.update(from: storage.advanced(by: offset), count: firstChunk)
        if firstChunk < toRead {
            destination.advanced(by: firstChunk).update(from: storage, count: toRead - firstChunk)
        }

        // Release: the copy above must complete before the producer can reuse those slots.
        readIndex.store(read + toRead, ordering: .releasing)
        return toRead
    }

    /// Consumer-side convenience. Allocates, so never call it from the audio thread.
    public func drain() -> [Float] {
        let available = availableFrames
        guard available > 0 else { return [] }
        var out = [Float](repeating: 0, count: available)
        let count = out.withUnsafeMutableBufferPointer { read(into: $0.baseAddress!, count: available) }
        if count < available { out.removeLast(available - count) }
        return out
    }

    /// Clears content and counters.
    ///
    /// NOT safe against a live producer - it is for between-utterance teardown, where the audio
    /// engine has already been stopped.
    public func reset() {
        writeIndex.store(0, ordering: .releasing)
        readIndex.store(0, ordering: .releasing)
        dropped.store(0, ordering: .releasing)
    }
}
