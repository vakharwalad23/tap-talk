import Foundation
import AVFAudio
import FluidAudio

/// True low-latency streaming via the NVIDIA Parakeet EOU 120M model (FluidAudio).
/// Chunk size = 320ms (best balance: ~5.7% WER, 14x RTFx). Token-level partial transcripts
/// arrive at ~320ms cadence — fast enough that text appears live as the user speaks.
///
/// EOU is a separate model from Parakeet v3; the user must explicitly download it.
actor EouStreamingEngine: StreamingTranscriber {
    // Sendable FIFO. The audio thread yields buffers synchronously, preserving arrival order.
    nonisolated let inputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let inputStream: AsyncStream<AVAudioPCMBuffer>

    private var manager: StreamingEouAsrManager?
    private var consumerTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<StreamingUpdate>.Continuation?
    private var updateStream: AsyncStream<StreamingUpdate>?

    enum EngineError: LocalizedError {
        case notInstalled
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Parakeet Realtime (EOU) model not installed — download it in Models"
            }
        }
    }

    init() {
        // ~20s buffer at 100Hz cpal callbacks. Sized to absorb model load latency on cold
        // start so the first words of an utterance aren't dropped before the consumer drains.
        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .bufferingNewest(2000))
        self.inputStream = stream
        self.inputContinuation = cont
    }

    // MARK: Model installation

    // FluidAudio stores EOU model files under this layout.
    nonisolated static func cacheBase() -> URL {
        guard let app = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("FluidAudio/Models/parakeet-eou-streaming")
        }
        return app.appendingPathComponent("FluidAudio/Models/parakeet-eou-streaming")
    }

    // SDK's loadModels(to:) appends "parakeet-eou-streaming/320ms" under the passed root.
    // cacheBase() already ends in "parakeet-eou-streaming", so the on-disk path is doubled.
    nonisolated static func variantDirectory() -> URL {
        cacheBase().appendingPathComponent("parakeet-eou-streaming/320ms")
    }

    private static let requiredFiles: [String] = [
        "streaming_encoder.mlmodelc",
        "decoder.mlmodelc",
        "joint_decision.mlmodelc",
        "vocab.json",
    ]

    nonisolated static func isInstalled() -> Bool {
        let dir = variantDirectory()
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    nonisolated static func sweepOrphans() {
        guard !isInstalled() else { return }
        let dir = cacheBase()
        if FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // User-initiated download. Loads the model once to verify the assets, then releases it.
    nonisolated static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let mgr = StreamingEouAsrManager(chunkSize: .ms320)
        try await mgr.loadModels(to: nil, configuration: nil) { p in
            progress(p.fractionCompleted)
        }
        await mgr.cleanup()
    }

    // Warms macOS Core ML JIT caches at app launch so the first streaming session's
    // engine.start() returns in hundreds of ms rather than seconds. Without this, the FIFO
    // can fill mid-utterance before the consumer drains. No-op if model isn't installed.
    nonisolated static func warmUp() async {
        guard isInstalled() else { return }
        let mgr = StreamingEouAsrManager(chunkSize: .ms320)
        _ = try? await mgr.loadModels()
        await mgr.cleanup()
    }

    nonisolated static func delete() throws {
        let dir = cacheBase()
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: StreamingTranscriber

    func start(sampleRate: Double) async throws {
        guard Self.isInstalled() else { throw EngineError.notInstalled }

        let mgr = StreamingEouAsrManager(chunkSize: .ms320)
        try await mgr.loadModels()
        self.manager = mgr

        let (out, outCont) = AsyncStream<StreamingUpdate>.makeStream()
        self.updateStream = out
        self.updateContinuation = outCont

        // Each new-tokens event re-emits the current partial. EOU tokens are stable
        // (no volatile tail), so confirmed = partial, volatile = "".
        await mgr.setPartialTranscriptCallback { [weak self] partial in
            Task { await self?.emitPartial(partial) }
        }

        // Drain FIFO input → manager.appendAudio + processBufferedAudio in arrival order.
        consumerTask = Task { [inputStream = self.inputStream, mgr] in
            for await buffer in inputStream {
                try? await mgr.appendAudio(buffer)
                try? await mgr.processBufferedAudio()
            }
        }
    }

    var updates: AsyncStream<StreamingUpdate> {
        updateStream ?? AsyncStream { $0.finish() }
    }

    func finish() async throws -> String {
        guard let mgr = manager else { return "" }
        let final = try await mgr.finish()
        updateContinuation?.yield(StreamingUpdate(confirmed: final, volatile: "", isFinal: true))
        updateContinuation?.finish()
        inputContinuation.finish()
        consumerTask?.cancel(); consumerTask = nil
        await mgr.cleanup()
        manager = nil
        return final
    }

    func cancel() async {
        inputContinuation.finish()
        consumerTask?.cancel(); consumerTask = nil
        if let mgr = manager {
            await mgr.cleanup()
        }
        updateContinuation?.finish()
        manager = nil
    }

    private func emitPartial(_ partial: String) {
        updateContinuation?.yield(StreamingUpdate(confirmed: partial, volatile: "", isFinal: false))
    }
}
