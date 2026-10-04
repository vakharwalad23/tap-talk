import Accelerate

/// First and last window that held speech, collected while a recording is scored.
public struct SpeechSpan: Equatable, Sendable {
    public private(set) var first: Int?
    public private(set) var last: Int?

    public init() {}

    /// Counts `window` as speech when its probability reaches the threshold.
    public mutating func record(window: Int, probability: Float) {
        guard probability >= SpeechTrim.threshold else { return }
        if first == nil { first = window }
        last = window
    }
}

/// Silence trimming rules, unchanged from the Rust implementation they replace.
public enum SpeechTrim {
    /// Rate of every trimmed clip.
    public static let sampleRate = 16_000
    /// Silero v5/v6 need exactly 512 samples at 16 kHz; larger windows clipped up to 2976 ms of speech.
    public static let windowSize = 512
    /// Below Silero's 0.5 default so murmured dictation still counts as speech.
    public static let threshold: Float = 0.35
    /// About 190 ms kept either side so soft onsets and tails survive.
    public static let paddingWindows = 6
    /// Shortest trimmed clip treated as a real utterance (~300 ms).
    public static let minSpeechSamples = sampleRate * 300 / 1000

    /// Samples to keep, or nil when no scored window held speech; partial trailing windows are never kept.
    public static func keptRange(span: SpeechSpan, sampleCount: Int) -> Range<Int>? {
        let windows = sampleCount / windowSize
        guard windows > 0, let first = span.first, let last = span.last else { return nil }
        let start = max(0, first - paddingWindows) * windowSize
        let end = min(min(last + paddingWindows + 1, windows) * windowSize, sampleCount)
        return start < end ? start..<end : nil
    }
}

/// Lifts quiet speech toward broadcast loudness; conversational audio passes untouched.
public enum AutomaticGain {
    static let targetRMS: Float = 0.0708   // -23 dBFS
    static let bypassRMS: Float = 0.0501   // -26 dBFS
    static let peakLimit: Float = 0.95
    static let maxGain: Float = 10         // about +20 dB, so near-silence is not blown into noise

    /// Scales `samples` in place and returns the gain applied (1 when untouched).
    @discardableResult
    public static func apply(to samples: inout [Float]) -> Float {
        guard !samples.isEmpty else { return 1 }
        let rms = vDSP.rootMeanSquare(samples)
        guard rms > .ulpOfOne, rms < bypassRMS else { return 1 }
        var gain = min(targetRMS / rms, maxGain)
        let peak = vDSP.maximumMagnitude(samples)
        if peak > 0, peak * gain > peakLimit { gain = peakLimit / peak }
        guard gain > 1 else { return 1 }
        let count = vDSP_Length(samples.count)
        samples.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var scale = gain
            vDSP_vsmul(base, 1, &scale, base, 1, count)
        }
        return gain
    }
}
