import Accelerate
import XCTest
@testable import TapTalkAudio

final class StreamingResamplerTests: XCTestCase {
    func testFortyEightKilohertzYieldsExactlyOneThirdAfterFinish() throws {
        let resampler = try StreamingResampler(sourceRate: 48_000)
        let out = try convert(resampler, sine(rate: 48_000, count: 153_600), chunk: 1_536)
        XCTAssertEqual(out.count, 51_200)
    }

    func testFortyFourOneUsesTheNonIntegerRatio() throws {
        let resampler = try StreamingResampler(sourceRate: 44_100)
        let out = try convert(resampler, sine(rate: 44_100, count: 141_100), chunk: 1_411)
        XCTAssertEqual(out.count, Int((141_100.0 * 16_000 / 44_100).rounded(.up)))
    }

    func testSixteenKilohertzPassesThroughUnchanged() throws {
        let resampler = try StreamingResampler(sourceRate: 16_000)
        let input = sine(rate: 16_000, count: 4_000)
        XCTAssertEqual(try convert(resampler, input, chunk: 512), input)
    }

    func testFinishLeavesTheConverterReadyForTheNextRecording() throws {
        let resampler = try StreamingResampler(sourceRate: 48_000)
        let input = sine(rate: 48_000, count: 48_000)
        let first = try convert(resampler, input, chunk: 1_536)
        let second = try convert(resampler, input, chunk: 1_536)
        XCTAssertEqual(first.count, 16_000)
        XCTAssertEqual(second.count, 16_000)
    }

    func testToneKeepsItsLevel() throws {
        let resampler = try StreamingResampler(sourceRate: 48_000)
        let out = try convert(resampler, sine(rate: 48_000, count: 96_000), chunk: 1_536)
        let middle = Array(out[4_000..<28_000])
        XCTAssertEqual(vDSP.rootMeanSquare(middle), 0.5 / Float(2).squareRoot(), accuracy: 0.01)
    }

    func testRejectsAZeroSampleRate() {
        XCTAssertThrowsError(try StreamingResampler(sourceRate: 0)) {
            XCTAssertEqual($0 as? AudioCaptureError, .unsupportedFormat(0))
        }
    }

    private func convert(_ resampler: StreamingResampler, _ input: [Float], chunk: Int) throws -> [Float] {
        var out: [Float] = []
        var index = 0
        while index < input.count {
            let end = min(index + chunk, input.count)
            try resampler.process(Array(input[index..<end]), into: &out)
            index = end
        }
        try resampler.finish(into: &out)
        return out
    }

    private func sine(rate: Double, count: Int) -> [Float] {
        (0..<count).map { 0.5 * sin(Float($0) * 2 * .pi * 440 / Float(rate)) }
    }
}
