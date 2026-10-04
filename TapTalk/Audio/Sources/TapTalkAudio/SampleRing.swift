import CoreAudio
import RingAtomics

/// Single-producer single-consumer ring of mono samples shared with the real-time audio thread.
// Unchecked: one producer (Writer, real-time thread) and one consumer (the pipeline actor); counters are published with release and read with acquire.
public final class SampleRing: @unchecked Sendable {
    /// Number of samples the ring holds.
    public let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    // [0] samples written, [1] samples read, [2] samples dropped; all monotonic, never reset.
    private let counters: UnsafeMutablePointer<Int64>

    /// Allocates the ring once; nothing is allocated afterwards on either side.
    public init(capacity: Int) {
        precondition(capacity > 0, "ring capacity must be positive")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        counters = .allocate(capacity: 3)
        counters.initialize(repeating: 0, count: 3)
    }

    deinit {
        storage.deallocate()
        counters.deallocate()
    }

    /// Producer handle for the real-time thread: raw pointers only, so no reference counting there.
    public var writer: Writer { Writer(storage: storage, capacity: capacity, counters: counters) }

    /// Total samples the producer has published.
    public var writtenCount: Int64 { tt_load_acquire(counters) }

    /// Total samples the producer dropped because the ring was full.
    public var droppedCount: Int64 { tt_load_acquire(counters + 2) }

    /// Discards every sample published before `mark`. Consumer side only.
    public func skip(to mark: Int64) {
        if mark > counters[1] { tt_store_release(counters + 1, mark) }
    }

    /// Appends published samples, up to `limit` when given, to `out`. Consumer side only.
    @discardableResult
    public func drain(into out: inout [Float], upTo limit: Int64? = nil) -> Int {
        let read = counters[1]
        var end = tt_load_acquire(counters)
        if let limit { end = min(end, limit) }
        let available = Int(end - read)
        guard available > 0 else { return 0 }
        let start = Int(read % Int64(capacity))
        let first = min(available, capacity - start)
        out.append(contentsOf: UnsafeBufferPointer(start: storage + start, count: first))
        if first < available {
            out.append(contentsOf: UnsafeBufferPointer(start: storage, count: available - first))
        }
        tt_store_release(counters + 1, end)
        return available
    }
}

extension SampleRing {
    /// Real-time producer: no locks, no allocation, no reference counting.
    // Unchecked: raw pointers into a SampleRing that outlives every audio callback using them.
    public struct Writer: @unchecked Sendable {
        fileprivate let storage: UnsafeMutablePointer<Float>
        fileprivate let capacity: Int
        fileprivate let counters: UnsafeMutablePointer<Int64>

        /// Publishes mono samples, or drops all of them and counts the drop when they do not fit.
        public func write(_ samples: UnsafeBufferPointer<Float>) {
            guard let base = samples.baseAddress, !samples.isEmpty,
                  let position = reserve(samples.count) else { return }
            let first = min(samples.count, capacity - position)
            (storage + position).update(from: base, count: first)
            if first < samples.count {
                storage.update(from: base + first, count: samples.count - first)
            }
            publish(samples.count)
        }

        /// Publishes the mono average of every channel in an audio buffer list.
        public func writeDownmix(_ list: UnsafePointer<AudioBufferList>, frames: Int) {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            if buffers.count == 1, buffers[0].mNumberChannels == 1, let data = buffers[0].mData {
                let count = min(frames, Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size)
                write(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
                return
            }
            var channels = 0
            var frameCount = frames
            for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
                let stride = Int(buffer.mNumberChannels)
                channels += stride
                frameCount = min(frameCount, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride))
            }
            guard channels > 0, frameCount > 0, let position = reserve(frameCount) else { return }
            let scale = 1 / Float(channels)
            var slot = position
            for frame in 0..<frameCount {
                var sum: Float = 0
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let stride = Int(buffer.mNumberChannels)
                    for channel in 0..<stride { sum += data[frame * stride + channel] }
                }
                storage[slot] = sum * scale
                slot = slot + 1 == capacity ? 0 : slot + 1
            }
            publish(frameCount)
        }

        // Ring position for `count` new samples, or nil (with the drop counted) when full.
        private func reserve(_ count: Int) -> Int? {
            let written = counters[0]
            let read = tt_load_acquire(counters + 1)
            guard count <= capacity - Int(written - read) else {
                tt_add_relaxed(counters + 2, Int64(count))
                return nil
            }
            return Int(written % Int64(capacity))
        }

        private func publish(_ count: Int) {
            tt_store_release(counters, counters[0] + Int64(count))
        }
    }
}
