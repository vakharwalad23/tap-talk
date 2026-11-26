import Cocoa
import Carbon.HIToolbox
import TapTalkHotkeys

/// Owns the listen-only event tap. Reports hotkey, key and mouse presses as `GestureInput`;
/// what they mean is decided by `HotkeyGesture` in the caller. Nothing is stored.
final class HotkeyService {
    static let shared = HotkeyService()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var onInput: ((GestureInput) -> Void)?
    private var healthTimer: Timer?

    private(set) var keyCode: UInt16 = UInt16(kVK_RightCommand)
    fileprivate var isHeld = false

    // nil while the Smart key is off; its modifier then counts as any other key.
    private(set) var smartKeyCode: UInt16?
    fileprivate var smartIsHeld = false

    /// A click inside the pill is not other input: its tick must finish, not cancel, a held press.
    var isExcludedClick: ((CGPoint) -> Bool)?

    var isTapAlive: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private init() {}

    func register(onInput: @escaping (GestureInput) -> Void) {
        self.onInput = onInput
        startTap()
        startHealthCheck()
    }

    func unregister() {
        healthTimer?.invalidate()
        healthTimer = nil
        stopTap()
        onInput = nil
    }

    func setKeyCode(_ code: UInt16) {
        isHeld = false
        keyCode = code
    }

    func setSmartKeyCode(_ code: UInt16?) {
        smartIsHeld = false
        smartKeyCode = code
    }

    static func flagMask(for keyCode: UInt16) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand:   return .maskCommand
        case kVK_Option, kVK_RightOption:     return .maskAlternate
        case kVK_Control, kVK_RightControl:   return .maskControl
        case kVK_Shift, kVK_RightShift:       return .maskShift
        default:                               return .maskCommand
        }
    }

    @discardableResult
    private func startTap() -> Bool {
        stopTap()

        // Key and mouse presses tell a shortcut (Right Cmd+C, Option-click) from a press of the
        // hotkey, and carry Escape. Listen-only, so nothing is delayed or swallowed.
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        isHeld = false
        smartIsHeld = false
    }

    // A release that lands while macOS has the tap disabled is never delivered, which left a
    // recording running and, with isHeld stuck, kept the health check from ever repairing the tap.
    // Called only once events may have been lost, so a held key ends there.
    // ponytail: a key still held at that moment ends early; the physical state is not readable
    // here (CGEventSource.keyState reports a held Right Cmd as released, measured 2026-11-19).
    fileprivate func releaseHeldKeys() {
        if isHeld {
            isHeld = false
            deliver(.hotkeyUp(.dictation))
        }
        if smartIsHeld {
            smartIsHeld = false
            deliver(.hotkeyUp(.smart))
        }
    }

    // Hops off the tap callback so a slow handler can never make macOS disable the tap.
    fileprivate func deliver(_ input: GestureInput) {
        DispatchQueue.main.async { self.onInput?(input) }
    }

    fileprivate func flagsInput(keyCode code: UInt16, flags: CGEventFlags, at time: TimeInterval) -> GestureInput? {
        if code == keyCode {
            let isDown = flags.contains(Self.flagMask(for: code))
            guard isDown != isHeld else { return nil }
            isHeld = isDown
            return isDown ? .hotkeyDown(.dictation, at: time) : .hotkeyUp(.dictation)
        }
        if let smart = smartKeyCode, code == smart {
            let isDown = flags.contains(Self.flagMask(for: code))
            guard isDown != smartIsHeld else { return nil }
            smartIsHeld = isDown
            return isDown ? .hotkeyDown(.smart, at: time) : .hotkeyUp(.smart)
        }
        return .otherInput(at: time)
    }

    // Catches the "silent inert tap" failure mode where tapDisabledByTimeout never fires.
    // Also recovers from taps disabled by system policy changes. A healthy tap is left alone,
    // held key or not: its release is still coming.
    private func startHealthCheck() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.onInput != nil else { return }

            guard let tap = self.eventTap else {
                self.startTap()
                return
            }

            if !CGEvent.tapIsEnabled(tap: tap) {
                self.releaseHeldKeys()
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) {
                    self.startTap()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // .listenOnly taps ignore the return value - passUnretained avoids leaking every event
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = service.eventTap {
            service.releaseHeldKeys()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // The paste and live typing post from this process; they are never the user's input.
    if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) {
        return Unmanaged.passUnretained(event)
    }

    // Uptime at delivery, not event.timestamp, whose unit differs between machines; only
    // differences between two events are used.
    let now = ProcessInfo.processInfo.systemUptime
    let input: GestureInput?
    switch type {
    case .flagsChanged:
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        input = service.flagsInput(keyCode: code, flags: event.flags, at: now)
    case .keyDown:
        // A key held from before the press repeats; only a new press is input.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            input = nil
        } else if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
            input = .escape
        } else {
            input = .otherInput(at: now)
        }
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        input = service.isExcludedClick?(event.location) == true ? nil : .otherInput(at: now)
    default:
        input = nil
    }

    if let input { service.deliver(input) }
    return Unmanaged.passUnretained(event)
}
