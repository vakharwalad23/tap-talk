import Foundation

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
/// fed via a Sendable FIFO continuation exposed by the engine, not through this protocol -
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
