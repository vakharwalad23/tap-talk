import Cocoa
import Carbon.HIToolbox

struct PasteService {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Marked transient and concealed so clipboard managers skip the entry. Without this every
        // dictation is archived by Clipboard History, Maccy, Paste and the rest — the transcript
        // outlives the paste, which is the opposite of what a local dictation tool should do. The
        // streaming path already did this; the batch path did not.
        //
        // declareTypes invalidates the previous contents as well as declaring the new ones, so it
        // replaces clearContents() rather than following it.
        pasteboard.declareTypes([.string, .transient, .concealed], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: .transient)
        pasteboard.setData(Data(), forType: .concealed)

        // Read back what our own write left the counter at, rather than assuming it advanced by
        // exactly one. Guessing wrong here fails silently in the worst direction: the restore is
        // skipped and the user's clipboard keeps the transcript.
        let ourChangeCount = pasteboard.changeCount

        simulateCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restorePasteboard(previous: previousContents, ourChangeCount: ourChangeCount)
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func restorePasteboard(previous: String?, ourChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        // Anything that wrote to the pasteboard in the meantime owns it now — leave it alone.
        guard pasteboard.changeCount == ourChangeCount else { return }
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }
}

extension NSPasteboard.PasteboardType {
    // Community conventions honored by clipboard managers (Maccy, Paste, Pastebot, …) and
    // macOS 26's built-in Clipboard History — they tell the manager to skip this item. Password
    // managers use the same markers. Every paste this app performs carries them, so a dictation
    // never outlives the paste it was written for.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
}
