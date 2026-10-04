import AVFoundation
import XCTest
@testable import TapTalkAudio

final class DictationRecorderTests: XCTestCase {
    func testWithoutDetectorRecordingIsUntrimmed() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.1, count: 16_000)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertEqual(audio.samples.count, 16_000)
        XCTAssertEqual(audio.speechSeconds, 1, accuracy: 1e-6)
        XCTAssertEqual(capture.pauses, 1)
    }

    func testSessionsNeverShareSamples() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.1, count: 16_000)
        let first = try await recorder.stop(.transcribe)
        try recorder.start()
        capture.feed(0.2, count: 8_000)
        let second = try await recorder.stop(.transcribe)
        XCTAssertTrue(first.samples.allSatisfy { $0 == 0.1 })
        XCTAssertEqual(second.samples.count, 8_000)
        XCTAssertTrue(second.samples.allSatisfy { $0 == 0.2 })
    }

    func testLateWritesAfterStopAreDiscarded() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.1, count: 8_000)
        _ = try await recorder.stop(.discard)
        capture.feed(0.9, count: 500)
        try recorder.start()
        capture.feed(0.2, count: 8_000)
        let next = try await recorder.stop(.transcribe)
        XCTAssertEqual(next.samples.count, 8_000)
        XCTAssertTrue(next.samples.allSatisfy { $0 == 0.2 })
    }

    func testStartTwiceAndStopWithoutStartAreRejected() async throws {
        let recorder = DictationRecorder(capture: FakeCapture())
        do {
            _ = try await recorder.stop(.transcribe)
            XCTFail("expected notRecording")
        } catch {
            XCTAssertEqual(error as? AudioCaptureError, .notRecording)
        }
        try recorder.start()
        XCTAssertThrowsError(try recorder.start()) { XCTAssertEqual($0 as? AudioCaptureError, .alreadyRecording) }
        _ = try await recorder.stop(.discard)
        XCTAssertFalse(recorder.isRecording)
    }

    func testDetectorTrimsLeadingAndTrailingSilenceAt48Kilohertz() async throws {
        let capture = FakeCapture(sampleRate: 48_000)
        let detector = FakeDetector()
        let recorder = DictationRecorder(capture: capture, detector: detector)
        try recorder.start()
        capture.feed(0, count: 48_000)
        capture.feed(0.3, count: 48_000)
        capture.feed(0, count: 48_000)
        let audio = try await recorder.stop(.transcribe)
        // Speech covers windows 31...62 of 93; six windows of padding each side keeps 25..<69 (44 windows).
        XCTAssertEqual(Double(audio.samples.count), Double(44 * 512), accuracy: 512)
        XCTAssertGreaterThanOrEqual(detector.calls, 93)
    }

    func testSilenceOnlyIsEmpty() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture, detector: FakeDetector())
        try recorder.start()
        capture.feed(0, count: 32_000)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertTrue(audio.samples.isEmpty)
        XCTAssertEqual(audio.speechSeconds, 0)
    }

    func testPressShorterThanMinimumIsEmpty() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.3, count: 3_200)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertTrue(audio.samples.isEmpty)
    }

    func testDetectorFailureFallsBackToUntrimmed() async throws {
        let capture = FakeCapture()
        let detector = FakeDetector()
        detector.failAfter = 5
        let recorder = DictationRecorder(capture: capture, detector: detector)
        try recorder.start()
        capture.feed(0, count: 16_000)
        capture.feed(0.3, count: 16_000)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertEqual(audio.samples.count, 32_000)
    }

    func testTwoMinuteRecordingKeepsEverySample() async throws {
        let capture = FakeCapture(sampleRate: 16_000, ringSeconds: 121)
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.1, count: 120 * 16_000)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertEqual(audio.samples.count, 120 * 16_000)
        XCTAssertEqual(capture.ring.droppedCount, 0)
    }

    func testStopReturnsWhatWasCapturedWhenDeliveryStops() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        try recorder.start()
        capture.feed(0.1, count: 12_000)
        try await Task.sleep(nanoseconds: 100_000_000)
        let audio = try await recorder.stop(.transcribe)
        XCTAssertEqual(audio.samples.count, 12_000)
    }

    func testLiveSinkGetsEverySampleAndSkipsVoiceActivity() async throws {
        let capture = FakeCapture(sampleRate: 48_000)
        let detector = FakeDetector()
        let recorder = DictationRecorder(capture: capture, detector: detector)
        let collected = Collected()
        try recorder.start(liveSink: { buffer in collected.add(Int(buffer.frameLength), rate: buffer.format.sampleRate) })
        capture.feed(0.3, count: 48_000)
        let audio = try await recorder.stop(.discard)
        XCTAssertTrue(audio.samples.isEmpty)
        XCTAssertEqual(collected.frames, 16_000)
        XCTAssertEqual(collected.rates, [16_000])
        XCTAssertEqual(detector.calls, 0)
    }

    func testLevelHandlerReportsRMS() async throws {
        let capture = FakeCapture()
        let recorder = DictationRecorder(capture: capture)
        let collected = Collected()
        recorder.setLevelHandler { collected.add(Int($0 * 1_000), rate: 0) }
        try recorder.start()
        capture.feed(0.25, count: 8_000)
        _ = try await recorder.stop(.discard)
        XCTAssertEqual(collected.frames / max(collected.count, 1), 250)
    }
}

/// Thread-safe accumulator for values reported from the pipeline.
final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    private var calls = 0
    private var seenRates: Set<Double> = []
    var frames: Int { lock.withLock { total } }
    var count: Int { lock.withLock { calls } }
    var rates: Set<Double> { lock.withLock { seenRates } }
    func add(_ value: Int, rate: Double) {
        lock.withLock {
            total += value
            calls += 1
            if rate > 0 { seenRates.insert(rate) }
        }
    }
}
