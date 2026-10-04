import AVFoundation
import XCTest
@testable import TapTalkAudio

final class SileroVoiceActivityTests: XCTestCase {
    func testSilenceIsNotSpeech() throws {
        let silero = try SileroVoiceActivity(modelURL: modelURL())
        let silence = [Float](repeating: 0, count: SpeechTrim.windowSize)
        for _ in 0..<20 {
            let probability = try silence.withUnsafeBufferPointer { try silero.speechProbability(window: $0) }
            XCTAssertLessThan(probability, SpeechTrim.threshold)
        }
    }

    func testResetMakesScoringRepeatable() throws {
        let silero = try SileroVoiceActivity(modelURL: modelURL())
        let clip = try speechClip()
        let first = try score(silero, clip, windows: 60)
        silero.reset()
        XCTAssertEqual(try score(silero, clip, windows: 60), first)
    }

    func testRejectsAWindowOfTheWrongSize() throws {
        let silero = try SileroVoiceActivity(modelURL: modelURL())
        let short = [Float](repeating: 0, count: 100)
        XCTAssertThrowsError(try short.withUnsafeBufferPointer { try silero.speechProbability(window: $0) }) {
            XCTAssertEqual($0 as? VoiceActivityError, .badWindow(100))
        }
    }

    // Measured on 2026-10-04: the Rust ONNX path keeps 20480..<269824 on this clip, and so does this model.
    func testRealClipTrimsLikeTheRustImplementation() throws {
        let silero = try SileroVoiceActivity(modelURL: modelURL())
        let clip = try speechClip()
        var span = SpeechSpan()
        let probabilities = try score(silero, clip, windows: clip.count / SpeechTrim.windowSize)
        for (window, probability) in probabilities.enumerated() { span.record(window: window, probability: probability) }
        XCTAssertEqual(SpeechTrim.keptRange(span: span, sampleCount: clip.count), 20_480..<269_824)
    }

    private func score(_ silero: SileroVoiceActivity, _ clip: [Float], windows: Int) throws -> [Float] {
        try clip.withUnsafeBufferPointer { all in
            try (0..<windows).map { window in
                let start = window * SpeechTrim.windowSize
                return try silero.speechProbability(window: UnsafeBufferPointer(rebasing: all[start..<(start + SpeechTrim.windowSize)]))
            }
        }
    }

    private func modelURL() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["TAPTALK_SILERO_MODEL"] else {
            throw XCTSkip("set TAPTALK_SILERO_MODEL to a silero-vad-unified-v6.0.0.mlmodelc")
        }
        return URL(fileURLWithPath: path)
    }

    private func speechClip() throws -> [Float] {
        guard let path = ProcessInfo.processInfo.environment["TAPTALK_SPEECH_CLIP"] else {
            throw XCTSkip("set TAPTALK_SPEECH_CLIP to a 16 kHz mono speech WAV")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
