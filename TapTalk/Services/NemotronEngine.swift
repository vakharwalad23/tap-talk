import Foundation
import FluidAudio

// NVIDIA Nemotron 3.5 ASR Streaming Multilingual (0.6B) via FluidAudio (Core ML / Apple
// Neural Engine). Covers the languages Parakeet does not, including Devanagari. The model
// is downloaded only on explicit user action from the model catalog - never auto-downloaded.
actor NemotronEngine {
    // 2240 ms is FluidAudio's default tier and measured best here: accuracy is flat above
    // 1120 ms while throughput peaks at 2240 ms.
    private static let chunkMs = 2240

    // Always the full-vocab bundle. "auto" routes to multilingual/; passing a Latin-script
    // code would route to the separate latin/ bundle and trigger a second ~640 MB download
    // for languages Parakeet already covers. The spoken language is supplied as a decoder
    // prompt instead, via setLanguage.
    private static let variant = "auto"

    // Languages this model can actually produce, with the exact prompt keys it recognizes.
    //
    // Both halves are verified against the shipped model, not assumed. Script coverage comes
    // from counting Unicode blocks in its 13,087-token vocabulary: Devanagari 196 tokens,
    // Arabic 252, CJK 6,907, Kana 217, Latin 2,567 - while Bengali, Gurmukhi, Gujarati,
    // Tamil, Telugu, Kannada and Malayalam have *zero*, so those are omitted rather than
    // offered and silently emitted as garbage. Keys come from the model's own
    // prompt_dictionary; bare codes that are not keys (e.g. "ja") resolve to auto-detect,
    // so the regional form is used where that is what the model ships.
    nonisolated static let supportedLanguages: [(id: String?, label: String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi"),
        ("mr-IN", "Marathi"),
        ("ur-PK", "Urdu"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja-JP", "Japanese"),
        ("zh-CN", "Chinese"),
    ]

    private var manager: StreamingNemotronMultilingualAsrManager?
    private var promptLanguage: String?

    enum EngineError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Nemotron 3.5 not installed - download it in Models"
            }
        }
    }

    nonisolated static func modelDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(Repo.nemotronMultilingual.folderName, isDirectory: true)
        return base
            .appendingPathComponent(
                StreamingNemotronMultilingualAsrManager.languageDirectory(for: variant),
                isDirectory: true
            )
            .appendingPathComponent("\(chunkMs)ms", isDirectory: true)
    }

    // Is the model present on disk? (No download.) metadata.json is written last by the
    // downloader, so its presence marks a complete variant.
    nonisolated static func isInstalled() -> Bool {
        FileManager.default.fileExists(
            atPath: modelDirectory().appendingPathComponent("metadata.json").path
        )
    }

    // User-initiated download with progress in [0, 1]. Called from the catalog UI.
    nonisolated static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            _ = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                languageCode: variant,
                chunkMs: chunkMs,
                progressHandler: { p in progress(p.fractionCompleted) }
            )
        } catch {
            sweepOrphans()   // remove a partially-downloaded variant dir
            throw error
        }
    }

    // Removes a partially-downloaded variant dir (present but incomplete) to reclaim disk.
    nonisolated static func sweepOrphans() {
        guard !isInstalled() else { return }
        let dir = modelDirectory()
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // Removes the downloaded model to reclaim disk. Deletes the whole repo folder rather
    // than the variant subdir so no empty parent is left behind.
    nonisolated static func delete() throws {
        let repoDir = modelDirectory()
            .deletingLastPathComponent()   // <chunkMs>ms
            .deletingLastPathComponent()   // multilingual
        if FileManager.default.fileExists(atPath: repoDir.path) {
            try FileManager.default.removeItem(at: repoDir)
        }
    }

    // Loads the already-downloaded model. Throws .notInstalled if absent - never downloads.
    func ensureLoaded() async throws {
        guard manager == nil else { return }
        guard Self.isInstalled() else { throw EngineError.notInstalled }
        let asr = StreamingNemotronMultilingualAsrManager()
        try await asr.loadModels(from: Self.modelDirectory())
        manager = asr
        promptLanguage = nil
    }

    // Releases the loaded model (and its ANE/RAM footprint) when the user switches engines.
    // cleanup() drops the Core ML models and caches the actor holds; dropping the reference
    // alone would leave them alive until the last continuation released it.
    func unload() async {
        await manager?.cleanup()
        manager = nil
        promptLanguage = nil
    }

    struct Output {
        let text: String
        let language: String
        let processingMs: UInt64
    }

    /// Transcribe one clip. `language` is a BCP-47-ish hint (e.g. "hi"); nil auto-detects.
    func transcribe(samples: [Float], language: String?) async throws -> Output {
        try await ensureLoaded()
        guard let manager else { throw EngineError.notInstalled }

        // Order matters and matches FluidAudio's own benchmark harness: set the language
        // first, then reset. reset() keeps the prompt id but re-seeds decoder state from the
        // current language, so resetting last is what leaves the two consistent.
        if promptLanguage != language {
            await manager.setLanguage(language)
            promptLanguage = language
        }
        // Clears the previous clip's audio, tokens and encoder cache.
        await manager.reset()

        let start = CFAbsoluteTimeGetCurrent()
        _ = try await manager.process(samples: samples)
        let text = try await manager.finish()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let detected = await manager.detectedLanguage()
        return Output(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            language: detected ?? language ?? "auto",
            processingMs: UInt64(max(0, elapsed) * 1000)
        )
    }
}
