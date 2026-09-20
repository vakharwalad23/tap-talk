// TapTalk-side TDT greedy decode without FluidAudio: Preprocessor, Encoder and Decoder from a
// compiled bundle, plus either the bundle's single-step joint or a K-frame batched joint. Scores
// K frames per joint call while the decoder projection is unchanged, so blank runs cost one call
// per K frames instead of one per frame. Writes hypotheses for bench/score.py and per-stage
// timings, so the zero-fill and the batching effects can be attributed separately.
@preconcurrency import CoreML
import AVFoundation
import Foundation

let blankId = 8192
let hiddenSize = 1024
let windowSamples = 240000
let durationBins = [0, 1, 2, 3, 4]
let maxSymbolsPerFrame = 10

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

struct Timing {
    var preprocessorMs = 0.0
    var encoderMs = 0.0
    var decodeMs = 0.0
    var decoderCalls = 0
    var jointCalls = 0
    var tokens = 0
    var totalMs: Double { preprocessorMs + encoderMs + decodeMs }
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func fail(_ message: String) -> Never {
    note(message)
    exit(1)
}

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard format.sampleRate == 16000, format.channelCount == 1 else { fail("expected 16 kHz mono: \(url.path)") }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        fail("buffer allocation failed")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData else { fail("no samples in \(url.path)") }
    return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
}

func loadModel(_ url: URL, _ units: MLComputeUnits) throws -> MLModel {
    let config = MLModelConfiguration()
    config.computeUnits = units
    return try MLModel(contentsOf: url, configuration: config)
}

func loadVocabulary(_ bundle: URL) throws -> [Int: String] {
    let data = try Data(contentsOf: bundle.appendingPathComponent("parakeet_vocab.json"))
    let raw = try JSONDecoder().decode([String: String].self, from: data)
    var vocabulary: [Int: String] = [:]
    for (key, value) in raw {
        if let id = Int(key) { vocabulary[id] = value }
    }
    guard vocabulary.count == 8192 else { fail("vocabulary has \(vocabulary.count) entries, expected 8192") }
    return vocabulary
}

final class Pipeline {
    let preprocessor: MLModel
    let encoder: MLModel
    let decoder: MLModel
    let joint: MLModel
    let vocabulary: [Int: String]
    // Frames scored per joint call: 1 for the shipped single-step graph, K for a batched graph.
    let k: Int
    let encoderInputName: String

    // Reused buffers: no allocation inside the decode loop.
    let audio: MLMultiArray
    let audioLength: MLMultiArray
    let targets: MLMultiArray
    let targetLength: MLMultiArray
    let encoderSteps: MLMultiArray

    init(bundle: URL, joint jointURL: URL?, encoderUnits: MLComputeUnits) throws {
        preprocessor = try loadModel(bundle.appendingPathComponent("Preprocessor.mlmodelc"), .cpuOnly)
        encoder = try loadModel(bundle.appendingPathComponent("Encoder.mlmodelc"), encoderUnits)
        decoder = try loadModel(bundle.appendingPathComponent("Decoder.mlmodelc"), .cpuOnly)
        joint = try loadModel(jointURL ?? bundle.appendingPathComponent("JointDecisionv3.mlmodelc"), .cpuOnly)
        vocabulary = try loadVocabulary(bundle)
        let inputs = joint.modelDescription.inputDescriptionsByName
        if let batched = inputs["encoder_steps"], let shape = batched.multiArrayConstraint?.shape {
            encoderInputName = "encoder_steps"
            k = shape[2].intValue
        } else if inputs["encoder_step"] != nil {
            encoderInputName = "encoder_step"
            k = 1
        } else {
            fail("joint model has neither encoder_steps nor encoder_step input")
        }
        audio = try MLMultiArray(shape: [1, NSNumber(value: windowSamples)], dataType: .float32)
        audioLength = try MLMultiArray(shape: [1], dataType: .int32)
        targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
        targetLength = try MLMultiArray(shape: [1], dataType: .int32)
        targetLength[0] = 1
        encoderSteps = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize), NSNumber(value: k)], dataType: .float32)
    }

    func transcribe(_ samples: [Float], timing: inout Timing) throws -> [Int] {
        var t0 = now()
        let count = min(samples.count, windowSamples)
        let audioPtr = audio.dataPointer.bindMemory(to: Float.self, capacity: windowSamples)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { audioPtr.update(from: base, count: count) }
        }
        if count < windowSamples { audioPtr.advanced(by: count).update(repeating: 0, count: windowSamples - count) }
        audioLength[0] = NSNumber(value: Int32(count))
        let mel = try preprocessor.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": audio, "audio_length": audioLength]))
        timing.preprocessorMs += now() - t0

        t0 = now()
        let encoded = try encoder.prediction(from: mel)
        timing.encoderMs += now() - t0
        guard let encoderOut = encoded.featureValue(for: "encoder")?.multiArrayValue,
              let lengthValue = encoded.featureValue(for: "encoder_length")?.multiArrayValue else {
            fail("encoder outputs missing")
        }
        let frames = Int(truncating: lengthValue[0])

        t0 = now()
        let tokens = try decode(encoderOut, frames: frames, timing: &timing)
        timing.decodeMs += now() - t0
        timing.tokens += tokens.count
        return tokens
    }

    private func runDecoder(token: Int, h: MLMultiArray, c: MLMultiArray, timing: inout Timing) throws -> MLFeatureProvider {
        targets[0] = NSNumber(value: Int32(token))
        timing.decoderCalls += 1
        return try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "targets": targets, "target_length": targetLength, "h_in": h, "c_in": c]))
    }

    // Greedy TDT (NeMo semantics): argmax token and argmax duration per frame; blank advances by
    // its duration without touching the decoder; a non-blank updates the decoder and re-scores.
    private func decode(_ encoderOut: MLMultiArray, frames: Int, timing: inout Timing) throws -> [Int] {
        let encPtr = encoderOut.dataPointer.bindMemory(to: Float.self, capacity: encoderOut.count)
        let hiddenStride = encoderOut.strides[1].intValue
        let timeStride = encoderOut.strides[2].intValue
        let stepPtr = encoderSteps.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize * k)

        var h = try MLMultiArray(shape: [2, 1, 640], dataType: .float32)
        var c = try MLMultiArray(shape: [2, 1, 640], dataType: .float32)
        memset(h.dataPointer, 0, h.count * 4)
        memset(c.dataPointer, 0, c.count * 4)
        var predicted = try runDecoder(token: blankId, h: h, c: c, timing: &timing)
        guard var decoderStep = predicted.featureValue(for: "decoder")?.multiArrayValue else { fail("decoder output missing") }
        var pendingH = predicted.featureValue(for: "h_out")?.multiArrayValue
        var pendingC = predicted.featureValue(for: "c_out")?.multiArrayValue

        var tokens: [Int] = []
        var t = 0
        var symbolsAtFrame = 0
        while t < frames {
            let block = min(k, frames - t)
            // Gather frames t ..< t+block as [1, 1024, K]; the tail of a short block is zero.
            for hIdx in 0..<hiddenSize {
                let src = encPtr.advanced(by: hIdx * hiddenStride + t * timeStride)
                let dst = stepPtr.advanced(by: hIdx * k)
                for j in 0..<block { dst[j] = src[j * timeStride] }
                for j in block..<k { dst[j] = 0 }
            }
            timing.jointCalls += 1
            let decision = try joint.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                encoderInputName: encoderSteps, "decoder_step": decoderStep]))
            guard let ids = decision.featureValue(for: "token_id")?.multiArrayValue,
                  let durations = decision.featureValue(for: "duration")?.multiArrayValue else {
                fail("joint outputs missing")
            }
            let idPtr = ids.dataPointer.bindMemory(to: Int32.self, capacity: ids.count)
            let durPtr = durations.dataPointer.bindMemory(to: Int32.self, capacity: durations.count)
            var i = 0
            while i < block {
                let token = Int(idPtr[i])
                var duration = durationBins[min(max(Int(durPtr[i]), 0), durationBins.count - 1)]
                if token == blankId {
                    duration = max(duration, 1)
                    symbolsAtFrame = 0
                    i += duration
                    t += duration
                    continue
                }
                tokens.append(token)
                symbolsAtFrame += 1
                if duration == 0 && symbolsAtFrame >= maxSymbolsPerFrame {
                    duration = 1
                    symbolsAtFrame = 0
                }
                // The decoder state changes, so the rest of this block is stale: re-score from t.
                let hIn = pendingH ?? h
                let cIn = pendingC ?? c
                predicted = try runDecoder(token: token, h: hIn, c: cIn, timing: &timing)
                guard let step = predicted.featureValue(for: "decoder")?.multiArrayValue else { fail("decoder output missing") }
                decoderStep = step
                h = hIn
                c = cIn
                pendingH = predicted.featureValue(for: "h_out")?.multiArrayValue
                pendingC = predicted.featureValue(for: "c_out")?.multiArrayValue
                t += duration
                break
            }
        }
        return tokens
    }

    func text(_ tokens: [Int]) -> String {
        tokens.compactMap { vocabulary[$0] }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func units(_ s: String) -> MLComputeUnits {
    switch s {
    case "gpu": return .cpuAndGPU
    case "cpu": return .cpuOnly
    case "all": return .all
    default: return .cpuAndNeuralEngine
    }
}

guard let bundlePath = arg("--bundle") else {
    fail("usage: ttdecode --bundle <dir> [--joint <batched.mlmodelc>] [--manifest m.json --out hyps.json] [--audio clip.wav --runs N] [--encoder-units ane|gpu|cpu]")
}
let bundle = URL(fileURLWithPath: bundlePath)
let jointURL = arg("--joint").map { URL(fileURLWithPath: $0) }
let pipeline = try Pipeline(bundle: bundle, joint: jointURL, encoderUnits: units(arg("--encoder-units") ?? "ane"))
note("bundle \(bundle.lastPathComponent), joint \(jointURL?.lastPathComponent ?? "JointDecisionv3.mlmodelc"), K=\(pipeline.k)")

if let manifestPath = arg("--manifest"), let outPath = arg("--out") {
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    let corpusDir = manifestURL.deletingLastPathComponent()
    var rows: [Row] = []
    var total = Timing()
    for fixture in manifest.fixtures {
        let samples = try loadSamples(corpusDir.appendingPathComponent(fixture.path))
        var timing = Timing()
        let tokens = try pipeline.transcribe(samples, timing: &timing)
        rows.append(Row(path: fixture.path, sha256: fixture.sha256, language: fixture.language,
                        text: pipeline.text(tokens), ms: timing.totalMs))
        total.preprocessorMs += timing.preprocessorMs
        total.encoderMs += timing.encoderMs
        total.decodeMs += timing.decodeMs
        total.decoderCalls += timing.decoderCalls
        total.jointCalls += timing.jointCalls
        total.tokens += timing.tokens
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outURL = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(rows).write(to: outURL)
    let n = Double(rows.count)
    note(String(format: "wrote %d rows to %@; per clip: pre %.1f enc %.1f decode %.1f ms, %.1f decoder + %.1f joint calls, %.1f tokens",
                rows.count, outPath, total.preprocessorMs / n, total.encoderMs / n, total.decodeMs / n,
                Double(total.decoderCalls) / n, Double(total.jointCalls) / n, Double(total.tokens) / n))
}

let audioArgs = CommandLine.arguments.enumerated().filter { $0.element == "--audio" }.map { CommandLine.arguments[$0.offset + 1] }
let runs = Int(arg("--runs") ?? "20") ?? 20
for path in audioArgs {
    let samples = try loadSamples(URL(fileURLWithPath: path))
    var warm = Timing()
    for _ in 0..<3 { _ = try pipeline.transcribe(samples, timing: &warm) }
    var totals: [Double] = []
    var pre: [Double] = []
    var enc: [Double] = []
    var dec: [Double] = []
    var last = Timing()
    var text = ""
    for _ in 0..<runs {
        var timing = Timing()
        let tokens = try pipeline.transcribe(samples, timing: &timing)
        totals.append(timing.totalMs)
        pre.append(timing.preprocessorMs)
        enc.append(timing.encoderMs)
        dec.append(timing.decodeMs)
        last = timing
        text = pipeline.text(tokens)
    }
    print(String(format: "%@ (%.2f s): total p50 %.2f ms | pre %.2f | enc %.2f | decode %.2f | %d decoder + %d joint calls, %d tokens, K=%d",
                 (path as NSString).lastPathComponent, Double(samples.count) / 16000, median(totals), median(pre), median(enc), median(dec),
                 last.decoderCalls, last.jointCalls, last.tokens, pipeline.k))
    print("  text: \(text)")
}
