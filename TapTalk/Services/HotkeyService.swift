import Cocoa
import Carbon.HIToolbox

final class HotkeyService {
    static let shared = HotkeyService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var onKeyDown: (() -> Void)?
    fileprivate var onKeyUp: (() -> Void)?

    private(set) var keyCode: UInt16 = UInt16(kVK_RightCommand)
    fileprivate(set) var isHeld = false

    private(set) var smartKeyCode: UInt16 = UInt16(kVK_Option)
    fileprivate(set) var smartIsHeld = false
    fileprivate var onSmartKeyDown: (() -> Void)?
    fileprivate var onSmartKeyUp: (() -> Void)?

    private init() {}

    func register(keyDown: @escaping () -> Void, keyUp: @escaping () -> Void) {
        onKeyDown = keyDown
        onKeyUp = keyUp
        startTap()
    }

    func unregister() {
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

    private func startTap() {
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
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()

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

    return Unmanaged.passRetained(event)
}
