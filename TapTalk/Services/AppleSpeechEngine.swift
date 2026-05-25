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
        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: return "No on-device Apple speech model available for this language"
            }
        }
    }

    func transcribe(samples: [Float], language: String?) async throws -> Output {
        let start = Date()

        let supported = await SpeechTranscriber.supportedLocales
        guard let locale = Self.resolveLocale(requested: language, supported: supported) else {
            throw EngineError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Ensure the locale's on-device model is present (no-op once installed).
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

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

    // Picks a supported locale: exact requested language, else the system language, else English.
    private static func resolveLocale(requested: String?, supported: [Locale]) -> Locale? {
        if let lang = requested, lang != "auto",
           let match = supported.first(where: { $0.language.languageCode?.identifier == lang }) {
            return match
        }
        let systemCode = Locale.current.language.languageCode?.identifier
        if let code = systemCode,
           let match = supported.first(where: { $0.language.languageCode?.identifier == code }) {
            return match
        }
        return supported.first(where: { $0.language.languageCode?.identifier == "en" }) ?? supported.first
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
