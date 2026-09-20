// Based on Oruk-AI/orukeet@347f646 export/coreml/benchmark/Sources/OrukeetCoreML (MIT).
// TapTalk maintains this copy: the bundle loads through FluidAudio's AsrModels.loadLocal,
// and the streaming wrapper the app never used is gone.
@preconcurrency import CoreML
import FluidAudio
import Foundation

public enum OrukeetModelError: Error, LocalizedError {
    case invalidVocabulary

    public var errorDescription: String? {
        "Orukeet requires the complete 8192-token v3 vocabulary"
    }
}

/// Loads an already-installed bundle directly, preserving Orukeet's identity.
/// FluidAudio's NVIDIA downloader/cache layout must not be used for this bundle.
public enum OrukeetLocalModels {
    /// Compile packages on the target device during installation, outside the
    /// transcription timer. Do not assume a macOS 26 cache works on macOS 14.
    public static func compilePackages(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
            let target = destination.appendingPathComponent("\(name).mlmodelc")
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            let compiled = try MLModel.compileModel(at: source.appendingPathComponent("\(name).mlpackage"))
            try FileManager.default.copyItem(at: compiled, to: target)
        }
        try FileManager.default.copyItem(
            at: source.appendingPathComponent("parakeet_vocab.json"),
            to: destination.appendingPathComponent("parakeet_vocab.json"))
    }

    /// Opens the compiled bundle with FluidAudio's local loader: v3 file names, preprocessor
    /// on the CPU, decoder and joint on the Neural Engine, encoder where asked.
    /// FluidAudio only requires ids 0..<8192 to exist; Orukeet ships exactly those, so any
    /// missing, extra or duplicate id means a wrong or damaged vocabulary file.
    public static func load(
        from directory: URL,
        encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine
    ) throws -> AsrModels {
        let data = try Data(contentsOf: directory.appendingPathComponent("parakeet_vocab.json"))
        let raw = try JSONDecoder().decode([String: String].self, from: data)
        let ids = Set(raw.keys.compactMap { Int($0) })
        guard raw.count == 8192, ids.count == 8192, ids.allSatisfy({ (0..<8192).contains($0) }) else {
            throw OrukeetModelError.invalidVocabulary
        }
        return try AsrModels.loadLocal(from: directory, encoderComputeUnits: encoderComputeUnits)
    }
}

/// TapTalk-compatible local engine. Input is mono 16 kHz PCM, as in ParakeetEngine.
/// The greedy bundle supports unconditioned decoding only: no language hint is passed,
/// so the joint's top-K outputs are never read.
public actor OrukeetEngine {
    private let modelDirectory: URL
    private let encoderComputeUnits: MLComputeUnits
    private var manager: AsrManager?

    public init(modelDirectory: URL, encoderComputeUnits: MLComputeUnits = .cpuAndNeuralEngine) {
        self.modelDirectory = modelDirectory
        self.encoderComputeUnits = encoderComputeUnits
    }

    @discardableResult
    public func ensureLoaded() throws -> AsrManager {
        if let manager { return manager }
        let models = try OrukeetLocalModels.load(from: modelDirectory, encoderComputeUnits: encoderComputeUnits)
        let loaded = AsrManager(config: .default, models: models)
        manager = loaded
        return loaded
    }

    public func unload() {
        manager = nil
    }

    public struct Output: Sendable {
        public let text: String
        public let processingMs: Double
    }

    public func transcribe(samples: [Float]) async throws -> Output {
        let manager = try ensureLoaded()
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        return Output(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            processingMs: result.processingTime * 1000)
    }
}
