import Foundation
import AVFAudio
import FluidAudio

/// Streaming transcriber backed by FluidAudio's sliding-window Parakeet engine.
/// Reuses the already-downloaded Parakeet v3 model — no extra download.
actor ParakeetStreamingEngine: StreamingTranscriber {
    // Sendable FIFO input pipe. The audio thread yields `AVAudioPCMBuffer`s directly;
    // a consumer task forwards them to FluidAudio in arrival order. This avoids the
    // "many Tasks racing into the actor" reordering bug that breaks streaming ASR.
    nonisolated let inputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let inputStream: AsyncStream<AVAudioPCMBuffer>

    private var manager: SlidingWindowAsrManager?
    private var consumerTask: Task<Void, Never>?
    private var observerTask: Task<Void, Never>?
    private var updateContinuation: AsyncStream<StreamingUpdate>.Continuation?
    private var updateStream: AsyncStream<StreamingUpdate>?
    private var inputFormat: AVAudioFormat?

    enum EngineError: LocalizedError {
        case notInstalled
        case invalidSampleRate(Double)
        var errorDescription: String? {
            switch self {
            case .notInstalled:             return "Parakeet model not installed — download it in Models"
            case .invalidSampleRate(let r): return "Unsupported source sample rate: \(r)"
            }
        }
    }

    init() {
        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .unbounded)
        self.inputStream = stream
        self.inputContinuation = cont
    }

    func start(sampleRate: Double) async throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw EngineError.invalidSampleRate(sampleRate)
        }
        self.inputFormat = format

        guard ParakeetEngine.isInstalled() else { throw EngineError.notInstalled }

        let models = try await AsrModels.loadFromCache(version: .v3)
        // .streaming preset: 1s hypothesis cadence, 2s context — far better for live
        // dictation than .default (15s chunks, 2s hypothesis, 10s left context).
        let mgr = SlidingWindowAsrManager(config: .streaming)
        try await mgr.loadModels(models)
        try await mgr.startStreaming(source: .microphone)   // label only
        self.manager = mgr

        // Outbound updates: one StreamingUpdate per FluidAudio tick, plus a final on finish().
        let (stream, continuation) = AsyncStream<StreamingUpdate>.makeStream()
        self.updateStream = stream
        self.updateContinuation = continuation

        // Drain our FIFO input → manager.streamAudio in arrival order.
        consumerTask = Task { [inputStream = self.inputStream, weak self] in
            for await buffer in inputStream {
                guard let self else { return }
                guard let mgr = await self.manager else { return }
                await mgr.streamAudio(buffer)
            }
        }

        // Drain FluidAudio ticks and re-emit as (confirmed, volatile) snapshots.
        observerTask = Task { [weak self] in
            guard let self else { return }
            for await _ in await mgr.transcriptionUpdates {
                if Task.isCancelled { return }
                let confirmed = await mgr.confirmedTranscript
                let volatileText = await mgr.volatileTranscript
                await self.emit(confirmed: confirmed, volatileText: volatileText)
                #if DEBUG
                print("tt-stream update confirmed=\"\(confirmed)\" volatile=\"\(volatileText)\"")
                #endif
            }
        }
    }

    /// Protocol entry point. The high-rate audio thread should prefer `inputContinuation`
    /// directly (sync, FIFO, no Task scheduling). This async path exists for protocol
    /// conformance and one-off feeds.
    func feed(_ samples: [Float]) async {
        guard let format = inputFormat, !samples.isEmpty,
              let buffer = makeBuffer(samples: samples, format: format) else { return }
        inputContinuation.yield(buffer)
    }

    var updates: AsyncStream<StreamingUpdate> {
        updateStream ?? AsyncStream { $0.finish() }
    }

    func finish() async throws -> String {
        guard let manager else { return "" }
        let final = try await manager.finish()
        updateContinuation?.yield(StreamingUpdate(confirmed: final, volatile: "", isFinal: true))
        updateContinuation?.finish()
        inputContinuation.finish()
        consumerTask?.cancel(); consumerTask = nil
        observerTask?.cancel(); observerTask = nil
        self.manager = nil
        return final
    }

    func cancel() async {
        inputContinuation.finish()
        consumerTask?.cancel(); consumerTask = nil
        observerTask?.cancel(); observerTask = nil
        await manager?.cancel()
        updateContinuation?.finish()
        manager = nil
    }

    private func emit(confirmed: String, volatileText: String) {
        updateContinuation?.yield(StreamingUpdate(confirmed: confirmed, volatile: volatileText, isFinal: false))
    }
}

/// Builds an AVAudioPCMBuffer from a mono Float32 sample array. Free function so the
/// audio-thread bridge can call it without entering the actor.
func makeBuffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    if let channel = buffer.floatChannelData?[0] {
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { channel.update(from: base, count: samples.count) }
        }
    }
    return buffer
}
