import Foundation
import AppKit
import PushTextCore

/// Headless proof that text injection reaches a real application.
///
/// The pure `ClipboardRestore` policy proves the decision; it proves nothing about whether a
/// synthetic Command-V actually lands, whether the layout lookup finds a key, or whether the
/// clipboard comes back. Those need the real pasteboard, the real event stream, and a real target.
///
/// `PUSHTEXT_INJECT_PROBE=1` runs it. `PUSHTEXT_INJECT_TEXT` is the string to inject (default
/// "pushtext probe"). `PUSHTEXT_INJECT_CLIPBOARD_ONLY=1` exercises the snapshot/restore round trip
/// WITHOUT sending any keystroke, which is the safe mode.
public enum InjectionProbe {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["PUSHTEXT_INJECT_PROBE"] == "1"
    }

    @MainActor
    public static func runAndExit() -> Never {
        let env = ProcessInfo.processInfo.environment
        let text = env["PUSHTEXT_INJECT_TEXT"] ?? "pushtext probe"
        // Settle delay overridable so #27 can SWEEP it per application rather than assert one
        // value. The delay is a race, and the only way to learn what a given app needs is to find
        // where it starts failing.
        let settleMillis = Double(env["PUSHTEXT_INJECT_SETTLE_MS"] ?? "") ?? 120
        let injector = PasteboardTextInjector(pasteSettleDelay: settleMillis / 1000)

        print("INJECT_PROBE trusted=\(injector.isTrusted)")
        print("INJECT_PROBE pasteKeyCode="
            + (PasteboardTextInjector.pasteKeyCode().map(String.init) ?? "none"))
        fflush(stdout)

        let pasteboard = NSPasteboard.general
        // Seed a known clipboard so the restore is checked against something specific rather than
        // against whatever happened to be there.
        let sentinel = "PUSHTEXT-SENTINEL-\(env["PUSHTEXT_INJECT_SENTINEL"] ?? "A")"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        print("INJECT_PROBE seeded=\(sentinel) changeCount=\(pasteboard.changeCount)")
        fflush(stdout)

        if env["PUSHTEXT_INJECT_CLIPBOARD_ONLY"] == "1" {
            runClipboardOnly(pasteboard: pasteboard, sentinel: sentinel, text: text)
            print("INJECT_PROBE finished")
            fflush(stdout)
            exit(0)
        }

        if let failure = injectBlocking(injector: injector, text: text) {
            print("INJECT_PROBE inject=failed error=\(failure)")
            fflush(stdout)
            exit(1)
        }
        print("INJECT_PROBE inject=sent text=\(text)")
        let back = pasteboard.string(forType: .string) ?? ""
        print("INJECT_PROBE clipboardRestored=\(back == sentinel) value=\(back)")
        print("INJECT_PROBE finished")
        fflush(stdout)
        exit(0)
    }

    /// Exercises both restore branches against the LIVE pasteboard, sending no keystroke.
    private static func runClipboardOnly(pasteboard: NSPasteboard, sentinel: String, text: String) {
        // Timed for #15. Release-to-text is finalize plus THIS - the pasteboard work standing
        // between a finished transcript and the Command-V that makes it appear. The 120 ms settle
        // delay is deliberately NOT in it: that wait happens after the key is posted, so it is
        // clipboard-restore hygiene rather than something the user sits through.
        //
        // Uses `stage`, not `setString`: staging writes one item carrying the text plus three
        // conceal markers (#41), so timing `setString` would measure a path production never runs.
        let clock = ContinuousClock()
        let t0 = clock.now
        let snap = PasteboardTextInjector.snapshot(pasteboard)
        let t1 = clock.now
        _ = PasteboardTextInjector.stage(text, on: pasteboard)
        let t2 = clock.now
        PasteboardTextInjector.restore(snap, to: pasteboard)
        let t3 = clock.now
        func ms(_ from: ContinuousClock.Instant, _ to: ContinuousClock.Instant) -> String {
            let span = to - from
            return String(format: "%.2f", Double(span.components.seconds) * 1000
                + Double(span.components.attoseconds) / 1_000_000_000_000_000)
        }
        print("INJECT_PROBE snapshot=\(ms(t0, t1))ms stage=\(ms(t1, t2))ms "
              + "restore=\(ms(t2, t3))ms chars=\(text.count)")
        fflush(stdout)

        // Branch 1: we are still the last writer, so the sentinel must come back.
        let saved = PasteboardTextInjector.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let mine = pasteboard.changeCount
        let decision = ClipboardRestore.decide(changeCountAfterOurWrite: mine,
                                               currentChangeCount: pasteboard.changeCount)
        print("INJECT_PROBE decision=\(decision)")
        PasteboardTextInjector.restore(saved, to: pasteboard)
        let back = pasteboard.string(forType: .string) ?? ""
        print("INJECT_PROBE restored=\(back == sentinel) value=\(back)")

        // Branch 2: another app writes after us. Their content must survive.
        let saved2 = PasteboardTextInjector.snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let mine2 = pasteboard.changeCount
        pasteboard.clearContents()
        pasteboard.setString("FOREIGN", forType: .string)
        let foreign = ClipboardRestore.decide(changeCountAfterOurWrite: mine2,
                                              currentChangeCount: pasteboard.changeCount)
        print("INJECT_PROBE foreignDecision=\(foreign)")
        if foreign == .restore { PasteboardTextInjector.restore(saved2, to: pasteboard) }
        print("INJECT_PROBE foreignPreserved="
            + "\((pasteboard.string(forType: .string) ?? "") == "FOREIGN")")
    }

    /// Bridges the async injector into the probe's synchronous flow.
    /// - Returns: a failure description, or nil on success.
    private static func injectBlocking(injector: PasteboardTextInjector, text: String) -> String? {
        let outcome = OutcomeBox()
        Task {
            do {
                try await injector.inject(text)
                outcome.set(nil)
            } catch {
                outcome.set("\(error)")
            }
        }

        // PUMP the run loop rather than blocking on a semaphore. `inject` hops to the main actor to
        // read the keyboard layout - Text Input Source calls trap off-main - so a blocking wait on
        // this thread deadlocks against the very work it is waiting for, and reports it as a
        // timeout. Observed exactly that: `inject=failed error=timeout` with the paste never sent.
        let deadline = Date().addingTimeInterval(15)
        while !outcome.isSettled, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return outcome.get()
    }
}

private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    private var settled = false
    func set(_ value: String?) { lock.lock(); failure = value; settled = true; lock.unlock() }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return settled ? failure : "timeout" }
    var isSettled: Bool { lock.lock(); defer { lock.unlock() }; return settled }
}
