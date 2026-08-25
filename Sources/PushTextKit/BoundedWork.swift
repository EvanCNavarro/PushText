import Foundation

/// Runs work on a detached thread and gives up waiting after a deadline (#178).
///
/// **Why this exists.** `NSPasteboard(name:)` can block forever. Measured on CI: it reaches
/// `CFPasteboardCreate` -> `_onqueue_CFPasteboardSetupInstance` ->
/// `dispatch_mach_send_with_result_and_wait_for_reply` and never gets an answer, because the
/// pasteboard server is intermittently unresponsive on a headless runner. That single call took the
/// whole test job down for ten minutes at a time, roughly one run in ten, and stayed undiagnosed
/// across three investigations because a hang leaves no output to read.
///
/// The blocked thread is DELIBERATELY abandoned rather than cancelled. A mach send waiting for a
/// reply cannot be interrupted from outside; the honest options are to leak one thread or to hang
/// the process, and a leaked thread in a test process that is about to exit is the cheaper of the
/// two. Do not "fix" this by joining the thread - that reintroduces the hang.
public enum BoundedWork {

    public struct TimedOut: Error, CustomStringConvertible {
        public let seconds: TimeInterval
        public let describing: String
        public var description: String {
            "\(describing) did not finish within \(seconds)s"
        }
    }

    /// The value, or `TimedOut` - never a wait without an end.
    /// `Value` is deliberately unconstrained. The thing this exists for - `NSPasteboard` - is not
    /// `Sendable`, and requiring it would exclude the only caller. Safe here because the closure
    /// CREATES the value on the worker thread and captures nothing: it crosses the boundary once,
    /// through a lock, and the waiting side does not touch it until the semaphore has been signalled.
    public static func run<Value>(
        _ describing: String,
        timeout: TimeInterval,
        work: @escaping @Sendable () -> Value
    ) throws -> Value {
        let box = Box<Value>()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let value = work()
            box.set(value)
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success, let value = box.get() else {
            throw TimedOut(seconds: timeout, describing: describing)
        }
        return value
    }

    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value?
        func set(_ newValue: Value) { lock.lock(); value = newValue; lock.unlock() }
        func get() -> Value? { lock.lock(); defer { lock.unlock() }; return value }
    }
}
