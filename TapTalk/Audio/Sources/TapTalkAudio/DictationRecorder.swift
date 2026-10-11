import Foundation
import os

/// One dictation at a time: conversion and voice activity run while recording, so stopping only
/// finishes the last few milliseconds of audio.
public final class DictationRecorder: Sendable {
    /// What stop does with the recording.
    public enum StopMode: Sendable {
        /// Trim, apply gain and return the samples for recognition.
        case transcribe
        /// Flush the tail to any live sink and return nothing.
        case discard
    }

    // One 512-sample VAD window of 16 kHz audio, so key-up leaves at most a window or two to score.
    private static let pumpInterval: UInt64 = 32_000_000

    private struct Active: Sendable {
        let session: CaptureSession
        let end: OSAllocatedUnfairLock<Int64?>
        let pump: Task<Void, Never>
    }

    private struct State: Sendable {
        var generation = 0
        var active: Active?
        var onLevel: LevelHandler?
    }

    private let capture: any AudioCapture
    private let pipeline: RecordingPipeline
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Recorder on the given capture; recordings stay untrimmed until a detector is loaded.
    public init(capture: any AudioCapture = MicrophoneCapture(), detector: sending VoiceActivityDetector? = nil) {
        self.capture = capture
        pipeline = RecordingPipeline(detector: detector)
    }

    /// Sets the level callback used by every following recording.
    public func setLevelHandler(_ handler: LevelHandler?) {
        state.withLock { $0.onLevel = handler }
    }

    /// Builds the audio graph so device setup happens before the first hotkey press.
    public func warmUp() throws {
        try capture.prepare()
    }

    /// Loads Silero; until this succeeds, recordings are transcribed untrimmed.
    public func loadVoiceActivity(modelURL: URL) async throws {
        try await pipeline.loadDetector(modelURL: modelURL)
    }

    /// True between a successful start and the matching stop.
    public var isRecording: Bool { state.withLock { $0.active != nil } }

    /// Starts recording; `liveSink`, when given, receives 16 kHz buffers instead of voice activity running.
    public func start(liveSink: LiveSink? = nil) throws {
        let capture = self.capture
        let pipeline = self.pipeline
        try state.withLock { state in
            guard state.active == nil else { throw AudioCaptureError.alreadyRecording }
            let session = try capture.start()
            state.generation += 1
            let generation = state.generation
            let end = OSAllocatedUnfairLock<Int64?>(initialState: nil)
            let onLevel = state.onLevel
            let pump = Task.detached(priority: .userInitiated) {
                await pipeline.begin(generation: generation, session: session, end: end, liveSink: liveSink, onLevel: onLevel)
                while !Task.isCancelled {
                    await pipeline.pump(generation: generation)
                    try? await Task.sleep(nanoseconds: Self.pumpInterval)
                }
            }
            state.active = Active(session: session, end: end, pump: pump)
        }
    }

    /// Stops recording and returns the finished audio (empty for `.discard`).
    public func stop(_ mode: StopMode) async throws -> RecordedAudio {
        let capture = self.capture
        let (pump, generation) = try state.withLock { state -> (Task<Void, Never>, Int) in
            guard let active = state.active else { throw AudioCaptureError.notRecording }
            state.active = nil
            capture.pause()
            let mark = active.session.ring.writtenCount
            active.end.withLock { $0 = mark }
            return (active.pump, state.generation)
        }
        pump.cancel()
        await pump.value
        return try await pipeline.finish(generation: generation, mode: mode)
    }

    /// Chooses the microphone the next recording uses.
    public func setInputPreference(_ preference: InputPreference) {
        capture.setInputPreference(preference)
    }

    /// Releases the audio hardware; call on app quit.
    public func shutdown() {
        capture.shutdown()
    }
}
