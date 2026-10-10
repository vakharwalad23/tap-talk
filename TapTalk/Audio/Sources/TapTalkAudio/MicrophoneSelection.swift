import CoreAudio

/// Which microphone recordings use.
public enum InputPreference: Sendable, Equatable {
    /// Whatever macOS has selected as the default input.
    case systemDefault
    /// The Mac's own microphone, so Bluetooth headphones stay in their high-quality mode.
    case builtIn
}

/// An input-capable Core Audio device, as much as choosing a microphone needs.
struct InputDeviceInfo: Equatable {
    let id: AudioDeviceID
    let isBuiltIn: Bool
}

/// Picks the Core Audio input device a recording uses.
public enum MicrophoneSelection {
    /// True when this Mac has a built-in microphone; Mac mini, Studio and Pro have none.
    public static var hasBuiltInMicrophone: Bool {
        inputDevices().contains(where: \.isBuiltIn)
    }

    /// The device to record from; the built-in microphone when preferred and present, else the system default.
    static func device(
        for preference: InputPreference, among devices: [InputDeviceInfo], systemDefault: AudioDeviceID
    ) -> AudioDeviceID? {
        if preference == .builtIn, let builtIn = devices.first(where: \.isBuiltIn) {
            return builtIn.id
        }
        return systemDefault == kAudioObjectUnknown ? nil : systemDefault
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
        return ids.filter(hasInput).map { InputDeviceInfo(id: $0, isBuiltIn: transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn) }
    }

    /// The input device macOS currently routes recordings to, or kAudioObjectUnknown.
    static func systemDefaultInput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : kAudioObjectUnknown
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr ? type : 0
    }
}
