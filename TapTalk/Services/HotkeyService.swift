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
        keyCode = code
    }

    private func startTap() {
        stopTap()

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap — accessibility permission required")
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
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == Int64(service.keyCode) {
            // Right Command: check if flag is set (key down) or cleared (key up)
            let rightCmdDown = flags.contains(.maskCommand) && keyCode == Int64(kVK_RightCommand)

            if rightCmdDown && !service.isHeld {
                service.isHeld = true
                DispatchQueue.main.async { service.onKeyDown?() }
            } else if !rightCmdDown && service.isHeld {
                service.isHeld = false
                DispatchQueue.main.async { service.onKeyUp?() }
            }
        }
    }

    return Unmanaged.passRetained(event)
}
