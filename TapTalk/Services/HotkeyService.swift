import Cocoa
import Carbon.HIToolbox

final class HotkeyService {
    static let shared = HotkeyService()

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var onKeyDown: (() -> Void)?
    fileprivate var onKeyUp: (() -> Void)?
    private var healthTimer: Timer?

    private(set) var keyCode: UInt16 = UInt16(kVK_RightCommand)
    fileprivate(set) var isHeld = false

    private(set) var smartKeyCode: UInt16 = UInt16(kVK_Option)
    fileprivate(set) var smartIsHeld = false
    fileprivate var onSmartKeyDown: (() -> Void)?
    fileprivate var onSmartKeyUp: (() -> Void)?

    var isTapAlive: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private init() {}

    func register(keyDown: @escaping () -> Void, keyUp: @escaping () -> Void) {
        onKeyDown = keyDown
        onKeyUp = keyUp
        startTap()
        startHealthCheck()
    }

    func unregister() {
        healthTimer?.invalidate()
        healthTimer = nil
        stopTap()
        onKeyDown = nil
        onKeyUp = nil
    }

    func setKeyCode(_ code: UInt16) {
        isHeld = false
        keyCode = code
    }

    func setSmartKeyCode(_ code: UInt16) {
        smartIsHeld = false
        smartKeyCode = code
    }

    func registerSmart(keyDown: @escaping () -> Void, keyUp: @escaping () -> Void) {
        onSmartKeyDown = keyDown
        onSmartKeyUp = keyUp
    }

    func unregisterSmart() {
        smartIsHeld = false
        onSmartKeyDown = nil
        onSmartKeyUp = nil
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

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

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
            DispatchQueue.main.async { self.onKeyUp?() }
        }
        if smartIsHeld {
            smartIsHeld = false
            DispatchQueue.main.async { self.onSmartKeyUp?() }
        }
    }

    // Catches the "silent inert tap" failure mode where tapDisabledByTimeout never fires.
    // Also recovers from taps disabled by system policy changes. A healthy tap is left alone,
    // held key or not: its release is still coming.
    private func startHealthCheck() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.onKeyDown != nil else { return }

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

    if type == .flagsChanged {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if eventKeyCode == service.keyCode {
            let mask = HotkeyService.flagMask(for: service.keyCode)
            let isDown = event.flags.contains(mask)
            if isDown && !service.isHeld {
                service.isHeld = true
                DispatchQueue.main.async { service.onKeyDown?() }
            } else if !isDown && service.isHeld {
                service.isHeld = false
                DispatchQueue.main.async { service.onKeyUp?() }
            }
        } else if eventKeyCode == service.smartKeyCode, service.onSmartKeyDown != nil {
            let mask = HotkeyService.flagMask(for: service.smartKeyCode)
            let isDown = event.flags.contains(mask)
            if isDown && !service.smartIsHeld {
                service.smartIsHeld = true
                DispatchQueue.main.async { service.onSmartKeyDown?() }
            } else if !isDown && service.smartIsHeld {
                service.smartIsHeld = false
                DispatchQueue.main.async { service.onSmartKeyUp?() }
            }
        }
    }

    return Unmanaged.passUnretained(event)
}
