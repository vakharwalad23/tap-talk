import AudioToolbox
import XCTest
@testable import TapTalkAudio

final class SampleRingTests: XCTestCase {
    func testDrainReturnsSamplesInOrderAcrossWraparound() {
        let ring = SampleRing(capacity: 8)
        var out: [Float] = []
        write(ring, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ring.drain(into: &out), 6)
        write(ring, [7, 8, 9, 10, 11])
        XCTAssertEqual(ring.drain(into: &out), 5)
        XCTAssertEqual(out, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    }

    func testFullRingDropsTheWholeWriteAndCountsIt() {
        let ring = SampleRing(capacity: 4)
        write(ring, [1, 2, 3])
        write(ring, [4, 5])
        var out: [Float] = []
        ring.drain(into: &out)
        XCTAssertEqual(out, [1, 2, 3])
        XCTAssertEqual(ring.droppedCount, 2)
        XCTAssertEqual(ring.writtenCount, 3)
    }

    func testDrainStopsAtTheLimitAndSkipDiscardsEarlierSamples() {
        let ring = SampleRing(capacity: 16)
        write(ring, [1, 2, 3, 4])
        let mark = ring.writtenCount
        write(ring, [5, 6])
        ring.skip(to: mark)
        var out: [Float] = []
        ring.drain(into: &out, upTo: mark + 1)
        XCTAssertEqual(out, [5])
        ring.drain(into: &out)
        XCTAssertEqual(out, [5, 6])
    }

    func testDownmixPassesMonoThrough() {
        let ring = SampleRing(capacity: 16)
        withBufferList([[0.25, -0.5, 1]]) { ring.writer.writeDownmix($0, frames: 3) }
        var out: [Float] = []
        ring.drain(into: &out)
        XCTAssertEqual(out, [0.25, -0.5, 1])
    }

    func testDownmixAveragesDeinterleavedChannels() {
        let ring = SampleRing(capacity: 16)
        withBufferList([[1, 0, 0.5], [0, 1, 0.5]]) { ring.writer.writeDownmix($0, frames: 3) }
        var out: [Float] = []
        ring.drain(into: &out)
        XCTAssertEqual(out, [0.5, 0.5, 0.5])
    }

    func testDownmixAveragesInterleavedStereo() {
        let ring = SampleRing(capacity: 16)
        withBufferList([[1, 0, 0.2, 0.4]], channelsPerBuffer: 2) { ring.writer.writeDownmix($0, frames: 2) }
        var out: [Float] = []
        ring.drain(into: &out)
        XCTAssertEqual(out[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(out[1], 0.3, accuracy: 1e-6)
    }

    func testDownmixNeverReadsPastTheBufferByteSize() {
        let ring = SampleRing(capacity: 16)
        withBufferList([[0.1, 0.2]]) { ring.writer.writeDownmix($0, frames: 10) }
        var out: [Float] = []
        ring.drain(into: &out)
        XCTAssertEqual(out.count, 2)
    }

    private func write(_ ring: SampleRing, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { ring.writer.write($0) }
    }

    // One AudioBuffer per array; channelsPerBuffer > 1 means that buffer is interleaved.
    private func withBufferList(
        _ buffers: [[Float]], channelsPerBuffer: UInt32 = 1,
        _ body: (UnsafePointer<AudioBufferList>) -> Void
    ) {
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        var storage: [UnsafeMutablePointer<Float>] = []
        for (index, samples) in buffers.enumerated() {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            pointer.initialize(from: samples, count: samples.count)
            storage.append(pointer)
            list[index] = AudioBuffer(
                mNumberChannels: channelsPerBuffer,
                mDataByteSize: UInt32(samples.count * MemoryLayout<Float>.size),
                mData: pointer)
        }
        body(UnsafePointer(list.unsafePointer))
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}
