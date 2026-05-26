import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox          // IsSecureEventInputEnabled
import ApplicationServices       // AXUIElement, AXValue

/// Types incremental transcription into the focused macOS app and reconciles when the
/// engine revises the volatile tail.
///
/// Two insertion paths, chosen per session:
/// 1. Accessibility range-replace (preferred) — selects the volatile tail via
///    `kAXSelectedTextRange` and overwrites via `kAXSelectedText`. Flicker-free, single
///    undo. Works on most native AppKit/SwiftUI text views.
/// 2. CGEvent Unicode keystrokes (fallback) — universal, including Electron / Terminal /
///    web fields where AX writes are blocked.
///
/// Not thread-safe; call from the main actor.
final class LiveInserter {
    private var inserted: String = ""
    private let source: CGEventSource?

    // AX fast-path state probed once per session in `begin()`.
    private var useAX = false
    private var sessionPID: pid_t = 0

    // Coalesces rapid hypothesis updates so we don't backspace+retype on every micro-revision.
    private var pendingWork: DispatchWorkItem?
    private let debounceSeconds: TimeInterval = 0.08

    init() {
        self.source = CGEventSource(stateID: .combinedSessionState)
    }

    // Starts a fresh session and snapshots the focused app for focus-loss detection.
    func begin() {
        pendingWork?.cancel(); pendingWork = nil
        inserted = ""
        if let (element, pid) = currentFocusedElement() {
            sessionPID = pid
            useAX = isAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString)
                 && isAttributeSettable(element, kAXSelectedTextAttribute as CFString)
        } else {
            sessionPID = 0
            useAX = false
        }
    }

    // Reconciles on-screen text with `confirmed + volatile`. Debounced.
    func update(confirmed: String, volatile: String) {
        guard !secureInputActive else { return }
        if focusChanged() { return }   // user switched apps; don't type into the new one
        let target = confirmed + volatile
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile(to: target) }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    // Finalizes the session: ensures the typed text matches `finalText`, then resets.
    // Returns true if the text was typed/replaced; false if dropped (secure input or focus moved).
    @discardableResult
    func commit(_ finalText: String) -> Bool {
        pendingWork?.cancel(); pendingWork = nil
        if secureInputActive || focusChanged() {
            inserted = ""
            return false
        }
        reconcile(to: finalText)
        inserted = ""
        return true
    }

    // Aborts the session: removes everything typed (if the focused field is still ours).
    func cancel() {
        pendingWork?.cancel(); pendingWork = nil
        let count = inserted.count
        if count > 0, !secureInputActive, !focusChanged() {
            backspace(count)
        }
        inserted = ""
    }

    // MARK: Reconciliation

    private func reconcile(to target: String) {
        let prefixCount = commonPrefixCount(inserted, target)
        let deleteCount = inserted.count - prefixCount
        let newTail = String(target.dropFirst(prefixCount))

        // Try the AX fast path first when available and the original focus still holds.
        if useAX, let element = focusedElementIfStill() {
            if axReplaceTail(element: element, deleteCount: deleteCount, with: newTail) {
                inserted = target
                return
            }
            // First failure → permanently disable AX path this session; CGEvent works everywhere.
            useAX = false
        }

        if deleteCount > 0 { backspace(deleteCount) }
        if !newTail.isEmpty { typeUnicode(newTail) }
        inserted = target
    }

    // Selects the tail range then sets the selected text. Returns false on any AX failure.
    private func axReplaceTail(element: AXUIElement, deleteCount: Int, with newTail: String) -> Bool {
        if deleteCount > 0 {
            guard let range = currentSelectedRange(element) else { return false }
            let caret = range.location + range.length
            guard caret >= deleteCount else { return false }
            let selection = CFRange(location: caret - deleteCount, length: deleteCount)
            guard setSelectedRange(element, selection) else { return false }
            return setSelectedText(element, newTail)
        }
        if !newTail.isEmpty {
            return setSelectedText(element, newTail)
        }
        return true
    }

    // MARK: AX helpers

    private func currentFocusedElement() -> (AXUIElement, pid_t)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let elem = focused else { return nil }
        let element = elem as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return (element, pid)
    }

    private func focusedElementIfStill() -> AXUIElement? {
        guard let (element, pid) = currentFocusedElement(), pid == sessionPID else { return nil }
        return element
    }

    private func focusChanged() -> Bool {
        guard sessionPID != 0 else { return false }
        guard let (_, pid) = currentFocusedElement() else { return true }
        return pid != sessionPID
    }

    private func isAttributeSettable(_ element: AXUIElement, _ attr: CFString) -> Bool {
        var settable: DarwinBoolean = false
        let err = AXUIElementIsAttributeSettable(element, attr, &settable)
        return err == .success && settable.boolValue
    }

    private func currentSelectedRange(_ element: AXUIElement) -> CFRange? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        let axValue = v as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var r = range
        guard let axValue = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    private func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    // MARK: CGEvent fallback path

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

    // Synthetic keys are blocked into secure-text fields; refuse rather than dropping chars.
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
