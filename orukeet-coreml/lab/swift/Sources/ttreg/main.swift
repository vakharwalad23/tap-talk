// Regression runner: transcribe every fixture of a sealed corpus with one compiled bundle and
// write the hypotheses for bench/score.py. Loads the four .mlmodelc files directly, nothing is
// downloaded, and each clip starts from a fresh decoder state exactly as TapTalk does.
@preconcurrency import CoreML
import AVFoundation
import FluidAudio
import Foundation

struct Fixture: Decodable {
    let path: String
    let sha256: String
    let language: String
}

struct Manifest: Decodable {
    let fixtures: [Fixture]
}

struct Row: Encodable {
    let path: String
    let sha256: String
    let language: String
    let text: String
    let ms: Double
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard format.sampleRate == 16000, format.channelCount == 1 else {
        throw NSError(domain: "ttreg", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected 16 kHz mono: \(url.path)"])
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "ttreg", code: 2, userInfo: [NSLocalizedDescriptionKey: "buffer allocation failed"])
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData else {
        throw NSError(domain: "ttreg", code: 3, userInfo: [NSLocalizedDescriptionKey: "no samples in \(url.path)"])
    }
    return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
}

func load(_ dir: URL, _ name: String, _ units: MLComputeUnits) throws -> MLModel {
    let config = MLModelConfiguration()
    config.computeUnits = units
    return try MLModel(contentsOf: dir.appendingPathComponent("\(name).mlmodelc"), configuration: config)
}

guard let bundlePath = arg("--bundle"), let manifestPath = arg("--manifest"), let outPath = arg("--out") else {
    note("usage: ttreg --bundle <dir> --manifest <manifest.json> --out <hyps.json>")
    exit(2)
}
let bundle = URL(fileURLWithPath: bundlePath)
let manifestURL = URL(fileURLWithPath: manifestPath)
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
let corpusDir = manifestURL.deletingLastPathComponent()

let vocabData = try Data(contentsOf: bundle.appendingPathComponent("parakeet_vocab.json"))
let raw = try JSONDecoder().decode([String: String].self, from: vocabData)
var vocabulary: [Int: String] = [:]
for (key, value) in raw {
    if let id = Int(key) { vocabulary[id] = value }
}
guard vocabulary.count == 8192 else {
    note("vocabulary has \(vocabulary.count) entries, expected 8192")
    exit(1)
}

let config = MLModelConfiguration()
config.computeUnits = .cpuAndNeuralEngine
let models = AsrModels(
    encoder: try load(bundle, "Encoder", .cpuAndNeuralEngine),
    preprocessor: try load(bundle, "Preprocessor", .cpuOnly),
    decoder: try load(bundle, "Decoder", .cpuAndNeuralEngine),
    joint: try load(bundle, "JointDecisionv3", .cpuAndNeuralEngine),
    configuration: config, vocabulary: vocabulary, version: .v3)
let manager = AsrManager(config: .default, models: models)
let layers = await manager.decoderLayerCount
note("loaded \(bundle.lastPathComponent), \(manifest.fixtures.count) fixtures")

var rows: [Row] = []
for fixture in manifest.fixtures {
    let samples = try loadSamples(corpusDir.appendingPathComponent(fixture.path))
    var state = TdtDecoderState.make(decoderLayers: layers)
    let result = try await manager.transcribe(samples, decoderState: &state)
    rows.append(Row(path: fixture.path, sha256: fixture.sha256, language: fixture.language,
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    ms: result.processingTime * 1000))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let outURL = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try encoder.encode(rows).write(to: outURL)
let median = rows.map(\.ms).sorted()[rows.count / 2]
note("wrote \(rows.count) rows to \(outPath), median \(String(format: "%.1f", median)) ms per clip")
