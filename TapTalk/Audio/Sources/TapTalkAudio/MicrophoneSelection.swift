import CoreAudio
import IOKit

/// An input-capable Core Audio device, as much as choosing a microphone needs.
struct InputDeviceInfo: Equatable {
    let id: AudioDeviceID
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

/// Picks the Core Audio input device a recording uses.
enum MicrophoneSelection {
    /// The built-in microphone in place of a Bluetooth default while the lid is open, else the system default.
    static func device(
        systemDefault: InputDeviceInfo?, builtIn: AudioDeviceID?, isLidClosed: () -> Bool
    ) -> AudioDeviceID? {
        // Recording from a Bluetooth microphone drops the headphones into low-quality headset mode,
        // and a closed lid disconnects the built-in microphone in hardware.
        if let systemDefault, systemDefault.isBluetooth, let builtIn, !isLidClosed() {
            return builtIn
        }
        return systemDefault?.id
    }

    /// The device the next recording should use, read from Core Audio now.
    static func currentDevice() -> AudioDeviceID? {
        let defaultID = systemDefaultInput()
        let systemDefault = defaultID == kAudioObjectUnknown
            ? nil : InputDeviceInfo(id: defaultID, transport: transportType(of: defaultID))
        let builtIn = inputDevices().first(where: \.isBuiltIn)?.id
        return device(systemDefault: systemDefault, builtIn: builtIn, isLidClosed: isLidClosed)
    }

    /// Every present device that has input streams.
    static func inputDevices() -> [InputDeviceInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInput).map { InputDeviceInfo(id: $0, transport: transportType(of: $0)) }
    }

    /// The input device macOS currently routes recordings to, or kAudioObjectUnknown.
    static func systemDefaultInput() -> AudioDeviceID {
        var device = kAudioObjectUnknown
        let found = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, into: &device)
        return found ? device : kAudioObjectUnknown
    }

    /// The format an IOProc receives from the device's first input stream.
    static func inputFormat(of device: AudioDeviceID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var stream = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &stream) == noErr else { return nil }
        var format = AudioStreamBasicDescription()
        return read(stream, kAudioStreamPropertyVirtualFormat, into: &format) ? format : nil
    }

    /// True while a MacBook's lid is closed; false on Macs without one.
    static func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var type: UInt32 = 0
        return read(device, kAudioDevicePropertyTransportType, into: &type) ? type : 0
    }

    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
