import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var listening = false
    @State private var keyCapture = KeyCapture()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Hotkey") {
                HStack {
                    Text("Push-to-talk key")
                    Spacer()
                    Button(listening ? "Press a modifier key…" : keyName(settings.hotkeyCode)) {
                        startListening()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(listening ? .orange : .primary)
                }

                Button("Reset to Right ⌘") {
                    applyKey(UInt16(kVK_RightCommand))
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onDisappear { keyCapture.stop() }
    }

    private func startListening() {
        listening = true
        keyCapture.start { code in
            applyKey(code)
            listening = false
        }
    }

    private func applyKey(_ code: UInt16) {
        settings.hotkeyCode = code
        HotkeyService.shared.setKeyCode(code)
    }

    private func keyName(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_RightCommand: return "Right ⌘"
        case kVK_RightOption:  return "Right ⌥"
        case kVK_RightControl: return "Right ⌃"
        case kVK_RightShift:   return "Right ⇧"
        case kVK_Command:      return "Left ⌘"
        case kVK_Option:       return "Left ⌥"
        case kVK_Control:      return "Left ⌃"
        case kVK_Shift:        return "Left ⇧"
        default:               return "Key \(code)"
        }
    }
}

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
    // Only capture actual modifier key presses (non-zero flags = key down)
    guard !event.flags.isEmpty else { return Unmanaged.passRetained(event) }
    DispatchQueue.main.async { capture.deliver(code) }
    return Unmanaged.passRetained(event)
}
