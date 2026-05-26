import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox   // IsSecureEventInputEnabled (HIServices)

/// Types incremental transcription into the focused macOS app and reconciles when the
/// engine revises the volatile tail. CGEvent-based: layout-independent insertion via
/// `CGEventKeyboardSetUnicodeString`, backspace via the Delete virtual key.
/// Not thread-safe; call from the main actor.
final class LiveInserter {
    private var inserted: String = ""
    private let source: CGEventSource?

    init() {
        self.source = CGEventSource(stateID: .combinedSessionState)
    }

    // Starts a fresh session. Call once per recording.
    func begin() {
        inserted = ""
    }

    // Reconciles the on-screen text with the latest hypothesis (confirmed + volatile).
    // Backspaces the divergent tail, types the new tail.
    func update(confirmed: String, volatile: String) {
        guard !secureInputActive else { return }
        reconcile(to: confirmed + volatile)
    }

    // Finalizes the session: ensures the typed text matches `finalText`, then resets.
    func commit(_ finalText: String) {
        guard !secureInputActive else { inserted = ""; return }
        reconcile(to: finalText)
        inserted = ""
    }

    // Aborts the session: removes everything typed this session.
    func cancel() {
        let count = inserted.count
        if count > 0, !secureInputActive { backspace(count) }
        inserted = ""
    }

    // MARK: Internals

    private func reconcile(to target: String) {
        let prefixCount = commonPrefixCount(inserted, target)
        let deleteCount = inserted.count - prefixCount
        if deleteCount > 0 { backspace(deleteCount) }
        let newTail = String(target.dropFirst(prefixCount))
        if !newTail.isEmpty { typeUnicode(newTail) }
        inserted = target
    }

    private func backspace(_ count: Int) {
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
            let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func typeUnicode(_ text: String) {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        utf16.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
                up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            }
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Synthetic keys are blocked into secure-text fields; detect and refuse rather than
    // silently dropping characters.
    private var secureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    private func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var ai = a.startIndex, bi = b.startIndex
        var count = 0
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            a.formIndex(after: &ai)
            b.formIndex(after: &bi)
            count += 1
        }
        return count
    }
}
