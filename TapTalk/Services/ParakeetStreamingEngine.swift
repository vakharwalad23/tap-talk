import Foundation
import AVFAudio
import FluidAudio

/// Streaming transcriber backed by FluidAudio's sliding-window Parakeet engine.
/// Reuses the already-downloaded Parakeet v3 model — no extra download.
actor ParakeetStreamingEngine: StreamingTranscriber {
    private var manager: SlidingWindowAsrManager?
    private var observerTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<StreamingUpdate>.Continuation?
    private var updateStream: AsyncStream<StreamingUpdate>?
    private var inputFormat: AVAudioFormat?

    enum EngineError: LocalizedError {
        case notInstalled
        case invalidSampleRate(Double)
        var errorDescription: String? {
            switch self {
            case .notInstalled:           return "Parakeet model not installed — download it in Models"
            case .invalidSampleRate(let r): return "Unsupported source sample rate: \(r)"
            }
        }
    }

    func start(sampleRate: Double) async throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw EngineError.invalidSampleRate(sampleRate)
        }
        self.inputFormat = format

        guard ParakeetEngine.isInstalled() else { throw EngineError.notInstalled }

        let models = try await AsrModels.loadFromCache(version: .v3)
        let mgr = SlidingWindowAsrManager(config: .default)
        try await mgr.loadModels(models)
        try await mgr.startStreaming(source: .microphone)   // label only; FluidAudio reads from streamAudio
        self.manager = mgr

        // Outbound stream: one StreamingUpdate per FluidAudio tick, plus a final on finish().
        let (stream, continuation) = AsyncStream<StreamingUpdate>.makeStream()
        self.updateStream = stream
        self.updateContinuation = continuation

        // Drain FluidAudio ticks and re-emit our combined (confirmed, volatile) snapshots.
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await _ in await mgr.transcriptionUpdates {
                if Task.isCancelled { return }
                let confirmed = await mgr.confirmedTranscript
                let volatileText = await mgr.volatileTranscript
                await self.emit(confirmed: confirmed, volatileText: volatileText)
            }
        }
    }

    func feed(_ samples: [Float]) async {
        guard let manager, let format = inputFormat, !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { channel.update(from: base, count: samples.count) }
            }
        }
        await manager.streamAudio(buffer)
    }

    // Each engine session has exactly one outbound stream, created in start().
    // Returning a finished stream is the safe fallback if updates is queried before start.
    var updates: AsyncStream<StreamingUpdate> {
        updateStream ?? AsyncStream { $0.finish() }
    }

    func finish() async throws -> String {
        guard let manager else { return "" }
        let final = try await manager.finish()
        updateContinuation?.yield(StreamingUpdate(confirmed: final, volatile: "", isFinal: true))
        updateContinuation?.finish()
        observerTask?.cancel()
        observerTask = nil
        self.manager = nil
        return final
    }

    func cancel() async {
        observerTask?.cancel()
        observerTask = nil
        await manager?.cancel()
        updateContinuation?.finish()
        manager = nil
    }

    private func emit(confirmed: String, volatileText: String) {
        updateContinuation?.yield(StreamingUpdate(confirmed: confirmed, volatile: volatileText, isFinal: false))
    }
}
