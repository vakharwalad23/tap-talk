import Foundation
import AVFAudio

/// One incremental hypothesis from a streaming engine.
/// - `confirmed`: text the engine is stable about; should not change.
/// - `volatile`: tentative tail that may be rewritten as more audio arrives.
/// - `isFinal`: true on the terminal update emitted after `finish()`.
struct StreamingUpdate: Sendable {
    let confirmed: String
    let volatile: String
    let isFinal: Bool
}

/// Common surface for any live-transcription engine. Implementations are actors. Audio is
/// fed via a Sendable FIFO continuation exposed by the engine, not through this protocol —
/// keeps the audio thread off the actor.
protocol StreamingTranscriber: Actor {
    /// Load models (if needed) and prepare to receive audio at the given sample rate.
    func start(sampleRate: Double) async throws

    /// Stream of incremental hypotheses. One stream per session.
    var updates: AsyncStream<StreamingUpdate> { get async }

    /// Flush remaining audio, drain the recognizer, return final joined text.
    func finish() async throws -> String

    /// Abort the session immediately; discards in-flight audio.
    func cancel() async
}

/// Wraps a mono Float32 sample array into an AVAudioPCMBuffer. Free function so the
/// audio-thread bridge can call it without entering an actor.
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
