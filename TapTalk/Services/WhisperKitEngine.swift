import Foundation
import WhisperKit

// Whisper via WhisperKit (Argmax) — full Core ML / Apple Neural Engine pipeline (encoder
// and decoder), 99 languages with built-in detection. A separate engine from the Rust
// whisper.cpp core. Models are downloaded only on explicit user action.
actor WhisperKitEngine {
    enum Model: String, CaseIterable, Sendable {
        case turbo
        case largeV3

        // Exact, unambiguous folder names in the argmaxinc/whisperkit-coreml repo.
        var variant: String {
            switch self {
            case .turbo:   return "openai_whisper-large-v3-v20240930_turbo_632MB"
            case .largeV3: return "openai_whisper-large-v3_947MB"
            }
        }
        var displayName: String {
            switch self {
            case .turbo:   return "Large v3 Turbo"
            case .largeV3: return "Large v3"
            }
        }
        var diskSizeMB: Int {
            switch self {
            case .turbo:   return 632
            case .largeV3: return 947
            }
        }
    }

    private var pipe: WhisperKit?
    private var loadedModel: Model?

    enum EngineError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "WhisperKit model not installed — download it in Models"
            }
        }
    }

    // Models live under the app's models dir so the catalog controls their disk footprint.
    nonisolated static func downloadBase() -> URL {
        URL(fileURLWithPath: AppController.modelsDirectory()).appendingPathComponent("whisperkit")
    }

    // The HuggingFace snapshot the WhisperKit downloader writes into.
    private static func repoDirectory() -> URL {
        downloadBase().appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }

    private static func variantCacheDirectory(_ model: Model) -> URL {
        repoDirectory().appendingPathComponent(".cache/huggingface/download/\(model.variant)")
    }

    private static func pathKey(_ model: Model) -> String { "whisperkit.path.\(model.rawValue)" }

    // The on-disk model folder returned by a prior download, if it still exists.
    nonisolated static func installedFolder(_ model: Model) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: pathKey(model)) else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    nonisolated static func isInstalled(_ model: Model) -> Bool {
        installedFolder(model) != nil
    }

    // User-initiated download with progress in [0, 1]. Called from the catalog UI.
    nonisolated static func download(_ model: Model, progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            let folder = try await WhisperKit.download(
                variant: model.variant,
                downloadBase: downloadBase(),
                progressCallback: { p in progress(p.fractionCompleted) }
            )
            UserDefaults.standard.set(folder.path, forKey: pathKey(model))
        } catch {
            // Leave no residue behind on a failed/cancelled download.
            try? FileManager.default.removeItem(at: repoDirectory().appendingPathComponent(model.variant))
            try? FileManager.default.removeItem(at: variantCacheDirectory(model))
            throw error
        }
    }

    nonisolated static func delete(_ model: Model) throws {
        let folder = installedFolder(model) ?? repoDirectory().appendingPathComponent(model.variant)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: variantCacheDirectory(model))
        UserDefaults.standard.removeObject(forKey: pathKey(model))
    }

    // Reclaims disk from downloads interrupted by an app quit, and re-adopts a complete
    // model folder whose install record was lost. Best-effort; run at launch.
    nonisolated static func sweepOrphans() {
        let fm = FileManager.default
        let repoDir = repoDirectory()
        guard fm.fileExists(atPath: repoDir.path) else { return }

        for model in Model.allCases {
            let folder = repoDir.appendingPathComponent(model.variant)
            guard fm.fileExists(atPath: folder.path) else { continue }
            if installedFolder(model) != nil { continue }   // recorded + present — keep

            let cache = variantCacheDirectory(model)
            if hasIncompleteArtifacts(cache) || isEmptyDirectory(folder) {
                try? fm.removeItem(at: folder)   // partial — reclaim
                try? fm.removeItem(at: cache)
            } else {
                // Complete folder, lost record — adopt it instead of re-downloading.
                UserDefaults.standard.set(folder.path, forKey: pathKey(model))
            }
        }
    }

    private static func hasIncompleteArtifacts(_ dir: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in walker where url.pathExtension == "incomplete" { return true }
        return false
    }

    private static func isEmptyDirectory(_ dir: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.isEmpty
    }

    func ensureLoaded(_ model: Model) async throws {
        if loadedModel == model, pipe != nil { return }
        guard let folder = Self.installedFolder(model) else { throw EngineError.notInstalled }
        let config = WhisperKitConfig(
            model: model.variant,
            modelFolder: folder.path,
            tokenizerFolder: folder,   // resolve the tokenizer locally — never hit the network
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        pipe = try await WhisperKit(config)
        loadedModel = model
    }

    struct Output {
        let text: String
        let language: String
        let processingMs: UInt64
    }

    func transcribe(samples: [Float], language: String?, model: Model) async throws -> Output {
        try await ensureLoaded(model)
        guard let pipe else { throw EngineError.notInstalled }

        let start = Date()
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = await pipe.transcribe(audioArrays: [samples], decodeOptions: options)
        let segments = results.first.flatMap { $0 } ?? []
        let text = segments.map { $0.text }.joined()
        let detected = segments.first?.language ?? language ?? "auto"
        let ms = UInt64(Date().timeIntervalSince(start) * 1000)
        return Output(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: detected,
            processingMs: ms
        )
    }

    // Releases the loaded model (and its ANE/RAM footprint) when the user switches engines.
    func unload() {
        pipe = nil
        loadedModel = nil
    }
}
