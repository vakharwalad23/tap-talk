import CoreML
import Foundation

/// Scores consecutive 512-sample windows of 16 kHz audio as speech or not.
public protocol VoiceActivityDetector: AnyObject {
    /// Clears recurrent state before a new recording.
    func reset()
    /// Speech probability of the next window; windows must arrive in order.
    func speechProbability(window: UnsafeBufferPointer<Float>) throws -> Float
}

/// Why a window could not be scored.
public enum VoiceActivityError: Error, Equatable {
    case badWindow(Int)
    case missingOutput
    case unexpectedOutputType
}

/// Silero VAD v6 as a 32 ms Core ML model, carrying LSTM state and 64 samples of context between
/// windows exactly as the reference implementation does.
public final class SileroVoiceActivity: VoiceActivityDetector {
    /// Folder name of the compiled model inside the models directory.
    public static let bundleName = "silero-vad-unified-v6.0.0.mlmodelc"
    private static let contextSize = 64
    private static let stateSize = 128

    private let model: MLModel
    private let audio: MLMultiArray
    private let hidden: MLMultiArray
    private let cell: MLMultiArray

    /// Loads the compiled model; throws when the bundle is missing or unreadable.
    public init(modelURL: URL) throws {
        let configuration = MLModelConfiguration()
        // Core ML plans every Silero op on the CPU anyway; cpuOnly skips the ANE compile at load (18 ms vs 43 ms).
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        audio = try MLMultiArray(shape: [1, NSNumber(value: SpeechTrim.windowSize + Self.contextSize)], dataType: .float32)
        hidden = try MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        cell = try MLMultiArray(shape: [1, NSNumber(value: Self.stateSize)], dataType: .float32)
        reset()
    }

    public func reset() {
        for array in [audio, hidden, cell] {
            array.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
                buffer.update(repeating: 0)
            }
        }
    }

    public func speechProbability(window: UnsafeBufferPointer<Float>) throws -> Float {
        guard window.count == SpeechTrim.windowSize, let source = window.baseAddress else {
            throw VoiceActivityError.badWindow(window.count)
        }
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            guard let base = buffer.baseAddress else { return }
            (base + Self.contextSize).update(from: source, count: SpeechTrim.windowSize)
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audio, "hidden_state": hidden, "cell_state": cell,
        ])
        let output = try model.prediction(from: input)
        guard let probability = output.featureValue(for: "vad_output")?.multiArrayValue,
              let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
              let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue
        else { throw VoiceActivityError.missingOutput }
        guard [probability, newHidden, newCell].allSatisfy({ $0.dataType == .float32 }) else {
            throw VoiceActivityError.unexpectedOutputType
        }
        Self.copy(newHidden, into: hidden)
        Self.copy(newCell, into: cell)
        // The last 64 samples of this window become the next window's context.
        audio.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            guard let base = buffer.baseAddress else { return }
            base.update(from: base + SpeechTrim.windowSize, count: Self.contextSize)
        }
        return probability.withUnsafeBufferPointer(ofType: Float.self) { $0.first ?? 0 }
    }

    private static func copy(_ source: MLMultiArray, into destination: MLMultiArray) {
        source.withUnsafeBufferPointer(ofType: Float.self) { from in
            destination.withUnsafeMutableBufferPointer(ofType: Float.self) { to, _ in
                guard let from = from.baseAddress, let base = to.baseAddress else { return }
                base.update(from: from, count: min(stateSize, to.count))
            }
        }
    }
}
