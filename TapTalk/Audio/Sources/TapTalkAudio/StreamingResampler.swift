import AVFoundation

/// Converts mono samples at the device rate to 16 kHz as they arrive, so key-up only flushes the
/// converter's short held-back tail instead of resampling the whole clip.
public final class StreamingResampler {
    /// Rate every recognition engine expects.
    public static let targetRate: Double = 16_000
    private static let bufferFrames: AVAudioFrameCount = 4_096

    /// Rate of the samples passed to `process`.
    public let sourceRate: Double
    private let converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat
    private var inputBuffer: AVAudioPCMBuffer
    private let outputBuffer: AVAudioPCMBuffer

    /// Builds a converter for `sourceRate`; 16 kHz input passes straight through.
    public init(sourceRate: Double) throws {
        guard sourceRate > 0,
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.targetRate, channels: 1, interleaved: false),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: Self.bufferFrames),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: Self.bufferFrames)
        else { throw AudioCaptureError.unsupportedFormat(sourceRate) }
        self.sourceRate = sourceRate
        inputFormat = input
        self.inputBuffer = inputBuffer
        self.outputBuffer = outputBuffer
        if sourceRate == Self.targetRate {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else {
                throw AudioCaptureError.unsupportedFormat(sourceRate)
            }
            // Max quality measured at ~0.4 ms per second of audio, all of it spent while recording.
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            self.converter = converter
        }
    }

    /// Appends the 16 kHz conversion of `samples` to `out`.
    public func process(_ samples: [Float], into out: inout [Float]) throws {
        guard !samples.isEmpty else { return }
        guard let converter else {
            out.append(contentsOf: samples)
            return
        }
        try load(samples)
        let buffer = inputBuffer
        var supplied = false
        try drain(converter, into: &out) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
    }

    /// Appends the converter's held-back tail and readies it for the next recording.
    public func finish(into out: inout [Float]) throws {
        guard let converter else { return }
        try drain(converter, into: &out) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        converter.reset()
    }

    /// Drops whatever an unfinished recording left inside the converter.
    public func reset() {
        converter?.reset()
    }

    private func load(_ samples: [Float]) throws {
        if inputBuffer.frameCapacity < AVAudioFrameCount(samples.count) {
            guard let bigger = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
                throw AudioCaptureError.conversion("input buffer allocation failed")
            }
            inputBuffer = bigger
        }
        guard let channel = inputBuffer.floatChannelData?[0] else {
            throw AudioCaptureError.conversion("input buffer has no channel data")
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
    }

    private func drain(
        _ converter: AVAudioConverter, into out: inout [Float], input: @escaping AVAudioConverterInputBlock
    ) throws {
        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: input)
            if let error { throw AudioCaptureError.conversion(error.localizedDescription) }
            if outputBuffer.frameLength > 0, let data = outputBuffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(outputBuffer.frameLength)))
            }
            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                throw AudioCaptureError.conversion("converter reported an error")
            @unknown default:
                return
            }
        }
    }
}
