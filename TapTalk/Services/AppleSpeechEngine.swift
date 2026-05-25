import Foundation
import AVFAudio
import Speech

// Apple's on-device SpeechTranscriber (Speech framework, macOS 26+). Runs entirely on
// device with no model download we manage — the language asset is fetched via the system
// AssetInventory. Fast and broad (CJK, Arabic, etc.), but locale-based: it does not
// auto-detect, so a locale is resolved from the requested language with sensible fallback.
@available(macOS 26, *)
actor AppleSpeechEngine {
    struct Output {
        let text: String
        let language: String
        let processingMs: UInt64
    }

    enum EngineError: LocalizedError {
        case unsupportedLocale
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: return "No on-device Apple speech model available for this language"
            case .notInstalled:      return "Apple Speech model not installed — download it in Settings"
            }
        }
    }

    // The locale currently reserved with AssetInventory — reused across calls.
    private var reservedLocale: Locale?

    func transcribe(samples: [Float], language: String?) async throws -> Output {
        let start = Date()

        let locale = try await prepare(language: language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        let audioFile = try Self.writeTempAudioFile(samples: samples)
        defer { try? FileManager.default.removeItem(at: audioFile.url) }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task { () -> AttributedString in
            var acc = AttributedString()
            for try await result in transcriber.results {
                acc += result.text
            }
            return acc
        }

        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        let attributed = try await collector.value

        let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = locale.language.languageCode?.identifier ?? "auto"
        let ms = UInt64(Date().timeIntervalSince(start) * 1000)
        return Output(text: text, language: lang, processingMs: ms)
    }

    // Resolves a supported locale, ensures its model is installed, and reserves a runtime
    // slot (required before analysis, or start() throws assetLocaleNotAllocated).
    private func prepare(language: String?) async throws -> Locale {
        let locale = try await Self.resolveLocale(requested: language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Never auto-download — the model must be installed explicitly (see installAsset).
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .unsupported else { throw EngineError.unsupportedLocale }
        guard status == .installed else { throw EngineError.notInstalled }

        if reservedLocale?.identifier != locale.identifier {
            if let previous = reservedLocale {
                _ = await AssetInventory.release(reservedLocale: previous)
            }
            _ = try await AssetInventory.reserve(locale: locale)
            reservedLocale = locale
        }
        return locale
    }

    // Releases the reserved locale slot when the engine is no longer in use.
    func unload() async {
        if let locale = reservedLocale {
            _ = await AssetInventory.release(reservedLocale: locale)
            reservedLocale = nil
        }
    }

    // Is the on-device model for this language already installed? (No download.)
    static func isAssetInstalled(language: String?) async -> Bool {
        guard let locale = try? await resolveLocale(requested: language) else { return false }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    // Explicit, user-initiated download of the language model. Progress in [0, 1].
    static func installAsset(language: String?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let locale = try await resolveLocale(requested: language)
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])

        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .unsupported else { throw EngineError.unsupportedLocale }
        guard status != .installed else { progress(1); return }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            progress(1); return
        }

        let poll = Task {
            while !Task.isCancelled {
                progress(request.progress.fractionCompleted)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        defer { poll.cancel() }
        try await request.downloadAndInstall()
        progress(1)
    }

    // Picks a supported locale: requested language, else the system language, else English.
    // Uses the SDK's equivalence resolver so script/region variants (zh→zh-CN) match.
    private static func resolveLocale(requested: String?) async throws -> Locale {
        if let lang = requested, lang != "auto",
           let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: lang)) {
            return match
        }
        if let system = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
            return system
        }
        if let english = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en")) {
            return english
        }
        guard let first = await SpeechTranscriber.supportedLocales.first else {
            throw EngineError.unsupportedLocale
        }
        return first
    }

    // 16 kHz mono Float32 samples → a temp WAV the analyzer can read (it handles conversion).
    private static func writeTempAudioFile(samples: [Float]) throws -> AVAudioFile {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw EngineError.unsupportedLocale
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: samples.count)
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tap-apple-\(UUID().uuidString).wav")
        let writeFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try writeFile.write(from: buffer)
        return try AVAudioFile(forReading: url)
    }
}

// Drives the explicit (opt-in) download of an Apple Speech language model from Settings.
@available(macOS 26, *)
@MainActor
final class AppleSpeechDownloadManager: ObservableObject {
    static let shared = AppleSpeechDownloadManager()

    @Published var installed = false
    @Published var downloading = false
    @Published var progress: Double = 0

    private init() {}

    func refresh(language: String?) {
        guard !downloading else { return }
        Task { installed = await AppleSpeechEngine.isAssetInstalled(language: language) }
    }

    func download(language: String?) {
        guard !downloading else { return }
        downloading = true
        progress = 0
        Task {
            do {
                try await AppleSpeechEngine.installAsset(language: language) { p in
                    Task { @MainActor in self.progress = p }
                }
                downloading = false
                installed = true
                AppController.shared.loadSelectedTier()
            } catch {
                downloading = false
                installed = await AppleSpeechEngine.isAssetInstalled(language: language)
            }
        }
    }
}
