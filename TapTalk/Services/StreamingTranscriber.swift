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

/// Common surface for any live-transcription engine. Implementations are actors so the
/// audio thread can `feed(_:)` without blocking the main thread.
protocol StreamingTranscriber: Actor {
    /// Load models (if needed) and prepare to receive audio. Sample rate is the rate at
    /// which `feed(_:)` will deliver samples; the engine resamples internally to its own rate.
    func start(sampleRate: Double) async throws

    /// Append a chunk of mono Float32 samples at the rate declared in `start(sampleRate:)`.
    /// Safe to call from any thread.
    func feed(_ samples: [Float]) async

    /// Stream of incremental hypotheses. The same engine instance vends one stream per session.
    var updates: AsyncStream<StreamingUpdate> { get async }

    /// Flush remaining audio, drain the recognizer, and return the final joined text.
    func finish() async throws -> String

    /// Abort the session immediately; discards any in-flight audio.
    func cancel() async
}
