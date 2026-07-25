import Foundation
import FluidAudio

// Local NVIDIA Parakeet (TDT 0.6B v3) engine via FluidAudio (Core ML / Apple Neural
// Engine). The model is downloaded
// only on explicit user action from the model catalog — never auto-downloaded.
actor ParakeetEngine {
    private static let version: AsrModelVersion = .v3

    private var manager: AsrManager?

    enum EngineError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Parakeet model not installed — download it in Models"
            }
        }
    }

    // Is the Parakeet model present on disk? (No download.)
    nonisolated static func isInstalled() -> Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    // User-initiated download with progress in [0, 1]. Called from the catalog UI.
    nonisolated static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            _ = try await AsrModels.download(version: version, progressHandler: { p in
                progress(p.fractionCompleted)
            })
        } catch {
            sweepOrphans()   // remove a partially-downloaded model dir
            throw error
        }
    }

    // Removes a partially-downloaded model dir (present but incomplete) to reclaim disk.
    nonisolated static func sweepOrphans() {
        guard !isInstalled() else { return }
        let dir = AsrModels.defaultCacheDirectory(for: version)
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // Removes the downloaded model to reclaim disk.
    nonisolated static func delete() throws {
        let dir = AsrModels.defaultCacheDirectory(for: version)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // Loads the already-downloaded model. Throws .notInstalled if absent — never downloads.
    func ensureLoaded() async throws {
        guard manager == nil else { return }
        guard Self.isInstalled() else { throw EngineError.notInstalled }
        let models = try await AsrModels.loadFromCache(version: Self.version)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    // Releases the loaded model (and its ANE/RAM footprint) when the user switches engines.
    func unload() {
        manager = nil
    }

    struct Output {
        let text: String
        let processingMs: UInt64
    }

    func transcribe(samples: [Float]) async throws -> Output {
        try await ensureLoaded()
        guard let manager else { throw EngineError.notInstalled }
        // Fresh decoder state per clip (batch use); layer count must match the model.
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return Output(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            processingMs: UInt64(max(0, result.processingTime) * 1000)
        )
    }
}
