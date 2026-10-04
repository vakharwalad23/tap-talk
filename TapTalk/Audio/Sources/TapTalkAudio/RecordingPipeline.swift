import Accelerate
import AVFoundation
import os

/// Receives 16 kHz buffers while a live-typing session records.
public typealias LiveSink = @Sendable (AVAudioPCMBuffer) -> Void
/// Receives the microphone RMS of the latest ~32 ms, about 30 times a second.
public typealias LevelHandler = @Sendable (Float) -> Void

/// A finished recording, ready for recognition.
public struct RecordedAudio: Sendable {
    /// Trimmed, gain-adjusted 16 kHz mono samples; empty when there was no usable speech.
    public let samples: [Float]
    /// Length of `samples` in seconds.
    public let speechSeconds: Float

    public static let empty = RecordedAudio(samples: [], speechSeconds: 0)
}

/// Owns everything between the ring and a finished recording: draining, conversion, voice
/// activity, the live sink, trimming and gain. One session at a time, keyed by generation.
actor RecordingPipeline {
    private static let reservedSamples = SpeechTrim.sampleRate * 30
    private let logger = Logger(subsystem: "talk.tap.app", category: "audio")

    private var detector: VoiceActivityDetector?
    private var generation = 0
    private var session: CaptureSession?
    private var end: OSAllocatedUnfairLock<Int64?>?
    private var resampler: StreamingResampler?
    private var failure: Error?
    private var liveSink: LiveSink?
    private var liveFormat: AVAudioFormat?
    private var onLevel: LevelHandler?
    private var speech: [Float] = []
    private var source: [Float] = []
    private var converted: [Float] = []
    private var scoredWindows = 0
    private var span = SpeechSpan()
    private var scoring = false
    private var droppedAtStart: Int64 = 0

    init(detector: VoiceActivityDetector?) {
        self.detector = detector
    }

    /// Loads Silero and scores one silent window so the first dictation skips Core ML's first-call cost.
    func loadDetector(modelURL: URL) throws {
        let silero = try SileroVoiceActivity(modelURL: modelURL)
        let silence = [Float](repeating: 0, count: SpeechTrim.windowSize)
        _ = try silence.withUnsafeBufferPointer { try silero.speechProbability(window: $0) }
        silero.reset()
        detector = silero
    }

    func begin(
        generation: Int, session: CaptureSession, end: OSAllocatedUnfairLock<Int64?>,
        liveSink: LiveSink?, onLevel: LevelHandler?
    ) {
        self.generation = generation
        self.session = session
        self.end = end
        session.ring.skip(to: session.startMark)
        droppedAtStart = session.ring.droppedCount
        failure = nil
        if resampler?.sourceRate == session.sampleRate {
            resampler?.reset()
        } else {
            do {
                resampler = try StreamingResampler(sourceRate: session.sampleRate)
            } catch {
                resampler = nil
                failure = error
            }
        }
        self.liveSink = liveSink
        self.onLevel = onLevel
        liveFormat = liveSink == nil ? nil : AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: StreamingResampler.targetRate, channels: 1, interleaved: false)
        if speech.capacity > Self.reservedSamples { speech = [] }
        speech.removeAll(keepingCapacity: true)
        speech.reserveCapacity(Self.reservedSamples)
        scoredWindows = 0
        span = SpeechSpan()
        detector?.reset()
        scoring = detector != nil && liveSink == nil
    }

    func pump(generation: Int) {
        guard generation == self.generation, session != nil else { return }
        drainAndProcess()
    }

    func finish(generation: Int, mode: DictationRecorder.StopMode) throws -> RecordedAudio {
        guard generation == self.generation, let session else { return .empty }
        defer { close() }
        drainAndProcess()
        if let resampler, failure == nil {
            converted.removeAll(keepingCapacity: true)
            do {
                try resampler.finish(into: &converted)
                accept(converted)
            } catch {
                failure = error
            }
        }
        let dropped = session.ring.droppedCount - droppedAtStart
        if dropped > 0 {
            logger.error("dropped \(dropped, privacy: .public) microphone samples: the pump fell behind")
        }
        if let failure { throw failure }
        return mode == .transcribe ? result() : .empty
    }

    private func drainAndProcess() {
        guard let session else { return }
        source.removeAll(keepingCapacity: true)
        guard session.ring.drain(into: &source, upTo: end?.withLock { $0 }) > 0 else { return }
        onLevel?(vDSP.rootMeanSquare(source))
        guard let resampler, failure == nil else { return }
        converted.removeAll(keepingCapacity: true)
        do {
            try resampler.process(source, into: &converted)
        } catch {
            failure = error
            return
        }
        accept(converted)
    }

    private func accept(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        speech.append(contentsOf: samples)
        if let liveSink, let liveFormat, let buffer = Self.buffer(samples, format: liveFormat) {
            liveSink(buffer)
        }
        if scoring { scoreCompleteWindows() }
    }

    private func scoreCompleteWindows() {
        guard let detector else { return }
        let size = SpeechTrim.windowSize
        do {
            try speech.withUnsafeBufferPointer { all in
                while (scoredWindows + 1) * size <= all.count {
                    let start = scoredWindows * size
                    let probability = try detector.speechProbability(
                        window: UnsafeBufferPointer(rebasing: all[start..<(start + size)]))
                    span.record(window: scoredWindows, probability: probability)
                    scoredWindows += 1
                }
            }
        } catch {
            scoring = false
            logger.error("voice activity failed, recording kept untrimmed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func result() -> RecordedAudio {
        let range: Range<Int>?
        if scoring {
            range = SpeechTrim.keptRange(span: span, sampleCount: speech.count)
        } else {
            range = speech.isEmpty ? nil : 0..<speech.count
        }
        guard let range, range.count >= SpeechTrim.minSpeechSamples else { return .empty }
        var samples = Array(speech[range])
        AutomaticGain.apply(to: &samples)
        return RecordedAudio(samples: samples, speechSeconds: Float(range.count) / Float(SpeechTrim.sampleRate))
    }

    private func close() {
        session = nil
        end = nil
        liveSink = nil
        liveFormat = nil
        onLevel = nil
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
