import Foundation

public enum HotkeyMode: String, Sendable, CaseIterable {
    case hold, toggle
}

public enum HotkeyID: Sendable, Equatable {
    case dictation, smart
}

public enum GestureInput: Sendable, Equatable {
    /// Seconds, from the event's timestamp.
    case hotkeyDown(HotkeyID, at: TimeInterval)
    case hotkeyUp(HotkeyID)
    /// Another key, another modifier or a mouse button went down.
    case otherInput(at: TimeInterval)
    case escape
}

public enum GestureAction: Sendable, Equatable {
    case start(HotkeyID), stop, cancel, cancelShortcut, pauseLiveTyping
}

/// Turns raw hotkey, key and mouse presses into recording actions for the chosen key mode.
public struct HotkeyGesture: Sendable {
    /// Other input this soon after the starting press makes it a shortcut, not a dictation.
    public static let shortcutWindow: TimeInterval = 1.0

    private enum Phase: Sendable, Equatable {
        case idle
        case pressing(HotkeyID, since: TimeInterval, paused: Bool)
        case toggledOn(paused: Bool)
    }

    public var mode: HotkeyMode
    private var phase: Phase = .idle

    public init(mode: HotkeyMode) {
        self.mode = mode
    }

    public mutating func handle(_ input: GestureInput, isRecording: Bool) -> GestureAction? {
        // The tick, the cross, the window's button or a failure ended the recording elsewhere.
        if !isRecording { phase = .idle }

        switch phase {
        case .idle:
            switch input {
            case .hotkeyDown(let id, let at):
                if !isRecording {
                    phase = .pressing(id, since: at, paused: false)
                    return .start(id)
                }
                return mode == .toggle ? .stop : nil
            case .escape:
                return isRecording ? .cancel : nil
            case .hotkeyUp, .otherInput:
                return nil
            }

        case .pressing(let id, let since, let paused):
            switch input {
            case .otherInput(let at):
                if at - since <= Self.shortcutWindow {
                    phase = .idle
                    return .cancelShortcut
                }
                // In toggle mode the caret may have moved under live typing; hold mode ends soon anyway.
                guard mode == .toggle, !paused else { return nil }
                phase = .pressing(id, since: since, paused: true)
                return .pauseLiveTyping
            case .hotkeyUp(let upID) where upID == id:
                if mode == .hold {
                    phase = .idle
                    return .stop
                }
                phase = .toggledOn(paused: paused)
                return nil
            case .escape:
                phase = .idle
                return .cancel
            case .hotkeyDown, .hotkeyUp:
                return nil
            }

        case .toggledOn(let paused):
            switch input {
            case .hotkeyDown:
                phase = .idle
                return .stop
            case .otherInput:
                guard !paused else { return nil }
                phase = .toggledOn(paused: true)
                return .pauseLiveTyping
            case .escape:
                phase = .idle
                return .cancel
            case .hotkeyUp:
                return nil
            }
        }
    }
}
