import Foundation

/// Failures surfaced to the user while recording a dictation.
public enum AudioCaptureError: LocalizedError, Equatable {
    case noInputDevice
    case permissionDenied
    case engineStart(String)
    case alreadyRecording
    case notRecording
    case unsupportedFormat(Double)
    case conversion(String)

    public var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone found"
        case .permissionDenied:
            return "Microphone access is off - allow TapTalk in System Settings > Privacy & Security > Microphone"
        case .engineStart(let reason):
            return "Could not start the microphone: \(reason)"
        case .alreadyRecording:
            return "Already recording"
        case .notRecording:
            return "Not recording"
        case .unsupportedFormat(let rate):
            return "Unsupported microphone sample rate (\(Int(rate)) Hz)"
        case .conversion(let reason):
            return "Audio conversion failed: \(reason)"
        }
    }
}
