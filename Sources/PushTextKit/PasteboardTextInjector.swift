import Foundation
import AppKit
import Carbon
import PushTextCore

/// Writes text into the frontmost application via the pasteboard and a synthetic Command-V.
///
/// **Why not the Accessibility API.** Setting `kAXValueAttribute` or `kAXSelectedTextAttribute`
/// returns `.success` WHILE DOING NOTHING in Electron apps, Chrome, VS Code, Google Docs and even
/// Pages — the write is accepted and discarded, so a caller that trusts the return code silently
/// loses the user's dictation. It is also barred outright under the App Sandbox. Five of five
/// surveyed open-source dictation apps use the pasteboard route (docs/research/04 sec 3).
///
/// **The clipboard is borrowed, not taken.** The previous contents are captured, restored
/// afterwards, and the restore is skipped entirely if anyone else wrote to the pasteboard in the
/// meantime — see `ClipboardRestore`.
public final class PasteboardTextInjector: TextInjector {

    public enum InjectionError: Error, Equatable {
        /// Accessibility (and therefore synthetic event posting) is not granted.
        case notTrusted
        /// No keycode on the current layout produces "v" with Command held.
        case pasteKeyUnavailable
        case eventCreationFailed
    }

    /// How long to wait after Command-V before restoring the clipboard.
    ///
    /// The paste is asynchronous: the target app reads the pasteboard when it processes the key
    /// event, which has not happened when `post` returns. Restoring too early hands it the OLD
    /// contents and the user gets their previous clipboard pasted instead of their words.
    private let pasteSettleDelay: TimeInterval

    public init(pasteSettleDelay: TimeInterval = 0.12) {
        self.pasteSettleDelay = pasteSettleDelay
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func inject(_ text: String) async throws {
        guard !text.isEmpty else { return }
        guard isTrusted else { throw InjectionError.notTrusted }
        guard let vKey = Self.pasteKeyCode() else { throw InjectionError.pasteKeyUnavailable }

        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let afterOurWrite = pasteboard.changeCount

        try Self.postCommandV(keyCode: vKey)

        try? await Task.sleep(for: .seconds(pasteSettleDelay))

        switch ClipboardRestore.decide(changeCountAfterOurWrite: afterOurWrite,
                                       currentChangeCount: pasteboard.changeCount) {
        case .restore:
            Self.restore(saved, to: pasteboard)
        case .skipForeignWrite:
            // Someone else owns the clipboard now. Losing our restore is a much smaller harm than
            // eating whatever the user just copied.
            break
        }
    }

    // MARK: - Keyboard layout

    /// The keycode that produces "v" **with Command held**, on the CURRENT layout.
    ///
    /// Hard-coding `kVK_ANSI_V` (9) is wrong on Dvorak-QWERTY-Command, where the layout deliberately
    /// reverts to QWERTY positions only while Command is down — so the answer differs depending on
    /// whether the modifier is applied. It is resolved WITH `cmdKey` for that reason.
    static func pasteKeyCode() -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let target = UniChar(UnicodeScalar("v").value)

        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            let modifiers = UInt32(cmdKey >> 8)
            for code in UInt16(0)...UInt16(127) {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers,
                                            UInt32(LMGetKbdType()),
                                            UInt32(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeyState, 4, &length, &chars)
                if status == noErr, length == 1, chars[0] == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    // MARK: - Event posting

    private static func postCommandV(keyCode: CGKeyCode) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw InjectionError.eventCreationFailed }

        down.flags = .maskCommand
        up.flags = .maskCommand
        // Post to the HID tap so the event enters where hardware would, ahead of session taps.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard snapshot

    /// Every representation of every item, so a restore preserves rich content rather than
    /// flattening the user's clipboard to plain text.
    struct Snapshot {
        var items: [[NSPasteboard.PasteboardType: Data]]
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { representations[type] = data }
            }
            if !representations.isEmpty { items.append(representations) }
        }
        return Snapshot(items: items)
    }

    static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            // The clipboard was empty before. Restoring emptiness is deliberate: leaving dictated
            // text behind would be both surprising and a small privacy leak.
            return
        }
        let restored = snapshot.items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
