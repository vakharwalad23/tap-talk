import AVFoundation
import Foundation

struct Clip: Decodable {
    let audio: String
    let ref: String
    let lang: String
}

enum BenchError: Error, CustomStringConvertible {
    case audio(String)
    case usage(String)
    var description: String {
        switch self {
        case .audio(let m): return "audio: \(m)"
        case .usage(let m): return "usage: \(m)"
        }
    }
}

// Read a 16 kHz mono wav as Float. The prep step writes exactly this format.
func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = file.processingFormat
    guard format.sampleRate == 16000, format.channelCount == 1 else {
        throw BenchError.audio(
            "expected 16 kHz mono, got \(Int(format.sampleRate)) Hz x \(format.channelCount): \(path)")
    }
    guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw BenchError.audio("buffer alloc failed for \(path)")
    }
    try file.read(into: buf)
    guard let ch = buf.floatChannelData else { throw BenchError.audio("no samples for \(path)") }
    return Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
}
