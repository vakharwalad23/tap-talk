import Foundation
import FluidAudio

// Local NVIDIA Parakeet (TDT 0.6B) engine via FluidAudio (Core ML / Apple Neural Engine).
// Runs on the already-captured 16 kHz mono samples — a second engine alongside the Rust
// whisper.cpp core, never touching the capture layer.
actor ParakeetEngine {
    private var manager: AsrManager?

    enum EngineError: LocalizedError {
        case notLoaded
        var errorDescription: String? {
            switch self {
            case .notLoaded: return "Parakeet model not loaded"
            }
        }
    }

    var isLoaded: Bool { manager != nil }

    // Downloads (first run) and loads the Parakeet v3 Core ML models. Idempotent.
    func ensureLoaded() async throws {
        guard manager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await ensureLoaded()
        guard let manager else { throw EngineError.notLoaded }
        // Fresh decoder state per clip (batch use); layer count must match the model.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
