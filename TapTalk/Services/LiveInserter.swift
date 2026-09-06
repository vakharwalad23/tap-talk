import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox          // IsSecureEventInputEnabled
import ApplicationServices       // AXUIElement, AXValue

/// Types incremental transcription into the focused macOS app and reconciles when the
/// engine revises the volatile tail.
///
/// Two insertion paths, chosen per session:
/// 1. Accessibility range-replace (preferred) - selects the volatile tail via
///    `kAXSelectedTextRange` and overwrites via `kAXSelectedText`. Flicker-free, single
///    undo. Works on most native AppKit/SwiftUI text views.
/// 2. Pasteboard + Cmd-V (fallback) - writes the new tail to the system pasteboard and
///    synthesizes Cmd-V. The only universally accepted insertion method on macOS; CGEvent
///    Unicode keystrokes are silently dropped by Chromium-based apps (VS Code, Mail
///    compose, browser body fields, Slack, Discord) because virtualKey=0 is ignored.
///
/// Not thread-safe; call from the main actor.
final class LiveInserter {
    private var inserted: String = ""
    private let source: CGEventSource?

    // AX fast-path state probed once per session in `begin()`.
    private var useAX = false
    private var sessionPID: pid_t = 0

    // Snapshot of the user's clipboard at session start. Restored after the final paste so
    // the streaming text doesn't replace whatever the user had copied.
    private var savedClipboard: String?
    // Scheduled restore. Cancelled (and performed synchronously) on a re-`begin()` so rapid
    // back-to-back sessions can't capture the transient text as their saved clipboard.
    private var pendingRestore: DispatchWorkItem?

    // Coalesces rapid hypothesis updates so the path doesn't backspace+retype on every
    // micro-revision.
    private var pendingWork: DispatchWorkItem?
    private let debounceSeconds: TimeInterval = 0.08

    init() {
        self.source = CGEventSource(stateID: .combinedSessionState)
    }

    // Starts a fresh session and snapshots the frontmost app for focus-loss detection.
    // Tracks the FRONTMOST APP's PID (via NSWorkspace), not the focused element's PID,
    // because Electron apps (VS Code, Slack, Discord, ...) run each window in a separate
    // helper process. The focused element's PID points at the helper and can jitter between
    // updates, which would falsely trip focusChanged() and bail out of typing entirely.
    // The frontmost-app PID is stable per app.
    func begin() {
        pendingWork?.cancel(); pendingWork = nil
        // Drain any pending clipboard restore from a prior session synchronously, so the
        // snapshot below captures the user's actual clipboard - not the transient text the
        // previous session pasted.
        if let restore = pendingRestore {
            restore.cancel()
            restore.perform()
            pendingRestore = nil
        }
        inserted = ""
        sessionPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        savedClipboard = NSPasteboard.general.string(forType: .string)
        if let (element, _) = currentFocusedElement() {
            useAX = isAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString)
                 && isAttributeSettable(element, kAXSelectedTextAttribute as CFString)
        } else {
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
            restoreClipboardSoon()
            return false
        }
        reconcile(to: finalText)
        inserted = ""
        restoreClipboardSoon()
        return true
    }

    // Aborts the session: removes everything typed (if the focused field is still the
    // session's target).
    func cancel() {
        pendingWork?.cancel(); pendingWork = nil
        let count = inserted.count
        if count > 0, !secureInputActive, !focusChanged() {
            backspace(count)
        }
        inserted = ""
        restoreClipboardSoon()
    }

    // Pastes use the system clipboard, so each session's last insert leaves the engine's
    // text on the user's pasteboard. Restore the original contents 200 ms after the final
    // Cmd-V completes (matches PasteService's delay pattern).
    private func restoreClipboardSoon() {
        let saved = savedClipboard
        savedClipboard = nil
        let work = DispatchWorkItem {
            if let saved {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(saved, forType: .string)
            }
        }
        pendingRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
            // First failure -> permanently disable AX path this session; pasteboard works everywhere.
            useAX = false
        }

        if deleteCount > 0 { backspace(deleteCount) }
        if !newTail.isEmpty { pasteInsert(newTail) }
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
        // SAFETY: kAXFocusedUIElementAttribute is contracted to return an AXUIElement.
        guard CFGetTypeID(elem) == AXUIElementGetTypeID() else { return nil }
        let element = elem as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return (element, pid)
    }

    // Returns the current focused element only if the frontmost app hasn't switched.
    // Intentionally does not compare the element's PID to sessionPID - the focused element
    // lives in an Electron helper process whose PID does not match the app's PID.
    private func focusedElementIfStill() -> AXUIElement? {
        guard !focusChanged() else { return nil }
        return currentFocusedElement()?.0
    }

    private func focusChanged() -> Bool {
        guard sessionPID != 0 else { return false }
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return current != sessionPID
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
        // SAFETY: kAXSelectedTextRangeAttribute is contracted to vend an AXValue.
        guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
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

    // Inserts text by writing it to the system pasteboard and synthesizing Cmd-V. The only
    // universally-accepted insertion method on macOS: CGEvent Unicode keystrokes are
    // silently dropped by Chromium-based apps (VS Code, Mail compose, browser body fields,
    // Slack, Discord) because they ignore key events with virtualKey=0. Pasting works
    // everywhere that paste works (which is essentially everywhere).
    //
    // Every paste is stamped with the community-standard "transient" and "concealed"
    // pasteboard types so well-behaved clipboard managers - including macOS 26's built-in
    // Clipboard History and third-party tools (Maccy / Paste / Pastebot) - skip the entry
    // and don't pollute the user's clipboard history with each volatile tail.
    //
    // virtualKey: kVK_ANSI_V = 0x09 with .maskCommand for Cmd-V.
    private func pasteInsert(_ text: String) {
        guard !text.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.string, .transient, .concealed], owner: nil)
        board.setString(text, forType: .string)
        board.setData(Data(), forType: .transient)
        board.setData(Data(), forType: .concealed)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
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
