import Accelerate
import XCTest
@testable import TapTalkAudio

final class SpeechTrimTests: XCTestCase {
    func testThresholdIsInclusive() {
        var span = SpeechSpan()
        span.record(window: 3, probability: 0.34)
        XCTAssertNil(span.first)
        span.record(window: 4, probability: 0.35)
        span.record(window: 9, probability: 0.9)
        span.record(window: 10, probability: 0.1)
        XCTAssertEqual(span.first, 4)
        XCTAssertEqual(span.last, 9)
    }

    func testNoSpeechKeepsNothing() {
        XCTAssertNil(SpeechTrim.keptRange(span: SpeechSpan(), sampleCount: 40 * 512))
    }

    func testSpeechInTheMiddleKeepsSixWindowsOfPaddingEachSide() {
        XCTAssertEqual(SpeechTrim.keptRange(span: span(10, 20), sampleCount: 40 * 512), 2_048..<13_824)
    }

    func testPaddingStopsAtTheStartOfTheClip() {
        XCTAssertEqual(SpeechTrim.keptRange(span: span(2, 5), sampleCount: 40 * 512)?.lowerBound, 0)
    }

    func testPartialTrailingWindowIsNeverKept() {
        XCTAssertEqual(SpeechTrim.keptRange(span: span(25, 29), sampleCount: 30 * 512 + 100)?.upperBound, 15_360)
    }

    func testClipShorterThanOneWindowKeepsNothing() {
        XCTAssertNil(SpeechTrim.keptRange(span: span(0, 0), sampleCount: 400))
    }

    func testGainBoostsQuietSpeechTowardTarget() {
        var samples = tone(amplitude: 0.01, count: 16_000)
        let before = vDSP.rootMeanSquare(samples)
        let gain = AutomaticGain.apply(to: &samples)
        let after = vDSP.rootMeanSquare(samples)
        XCTAssertGreaterThan(gain, 1)
        XCTAssertGreaterThan(after, before)
        XCTAssertTrue(after > 0.04 && after < 0.10, "after rms \(after)")
    }

    func testGainBypassesConversationalLevel() {
        var samples = tone(amplitude: 0.2, count: 16_000)
        let original = samples
        XCTAssertEqual(AutomaticGain.apply(to: &samples), 1)
        XCTAssertEqual(samples, original)
    }

    func testGainIsLimitedByThePeak() {
        var samples = [Float](repeating: 0.001, count: 16_000)
        samples[100] = 0.5
        let gain = AutomaticGain.apply(to: &samples)
        XCTAssertEqual(gain, 0.95 / 0.5, accuracy: 1e-4)
        XCTAssertLessThanOrEqual(vDSP.maximumMagnitude(samples), 0.95 + 1e-5)
    }

    func testGainLeavesSilenceAlone() {
        var samples = [Float](repeating: 0, count: 1_000)
        XCTAssertEqual(AutomaticGain.apply(to: &samples), 1)
        XCTAssertEqual(samples, [Float](repeating: 0, count: 1_000))
    }

    private func span(_ first: Int, _ last: Int) -> SpeechSpan {
        var span = SpeechSpan()
        span.record(window: first, probability: 1)
        span.record(window: last, probability: 1)
        return span
    }

    private func tone(amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { amplitude * sin(Float($0) * 0.2) }
    }
}
