import Cocoa
import Carbon.HIToolbox

// Captures a single modifier keypress so the user can rebind a hotkey. Lives beside the other
// event-tap code rather than inside a settings view — both settings pages use it, and a view is
// the wrong owner for something that installs a system-wide tap.
final class KeyCapture {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onCapture: ((UInt16) -> Void)?

    func start(onCapture: @escaping (UInt16) -> Void) {
        stop()
        self.onCapture = onCapture

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyCaptureCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        tap = nil
        source = nil
        onCapture = nil
    }

    fileprivate func deliver(_ code: UInt16) {
        let cb = onCapture
        stop()
        cb?(code)
    }
}

private func keyCaptureCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo, type == .flagsChanged else {
        return Unmanaged.passRetained(event)
    }
    let capture = Unmanaged<KeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard !event.flags.isEmpty else { return Unmanaged.passRetained(event) }
    DispatchQueue.main.async { capture.deliver(code) }
    return Unmanaged.passRetained(event)
}
