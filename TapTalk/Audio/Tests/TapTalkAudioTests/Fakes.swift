import Accelerate
import Foundation
@testable import TapTalkAudio

/// Capture that tests drive by hand, playing the real-time producer through the ring writer.
final class FakeCapture: AudioCapture, @unchecked Sendable {
    let ring: SampleRing
    let sampleRate: Double
    private(set) var pauses = 0

    init(sampleRate: Double = 16_000, ringSeconds: Double = 4) {
        self.sampleRate = sampleRate
        ring = SampleRing(capacity: Int(sampleRate * ringSeconds))
    }

    func prepare() throws {}
    func start() throws -> CaptureSession { CaptureSession(ring: ring, sampleRate: sampleRate, startMark: ring.writtenCount) }
    func pause() { pauses += 1 }
    func shutdown() {}

    func feed(_ value: Float, count: Int, chunk: Int = 1_536) {
        var remaining = count
        let block = [Float](repeating: value, count: chunk)
        while remaining > 0 {
            let n = min(chunk, remaining)
            block.withUnsafeBufferPointer { ring.writer.write(UnsafeBufferPointer(rebasing: $0[0..<n])) }
            remaining -= n
        }
    }
}

/// Detector that calls a window speech when its RMS is above 0.05, and can fail on demand.
final class FakeDetector: VoiceActivityDetector, @unchecked Sendable {
    private(set) var calls = 0
    var failAfter: Int?

    func reset() {}

    func speechProbability(window: UnsafeBufferPointer<Float>) throws -> Float {
        calls += 1
        if let failAfter, calls > failAfter { throw VoiceActivityError.missingOutput }
        return vDSP.rootMeanSquare(window) > 0.05 ? 1 : 0
    }
}
