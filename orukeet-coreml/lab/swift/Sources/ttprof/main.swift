// Per-component and end-to-end latency profile of a compiled Orukeet or Parakeet v3 Core ML
// bundle through FluidAudio. Loads the four .mlmodelc files from --dir; nothing is downloaded.
@preconcurrency import CoreML
import AVFoundation
import FluidAudio
import Foundation

func arg(_ name: String, _ def: String) -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return def
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }
func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
func p95(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return 0 }
    return s[min(s.count - 1, Int(Double(s.count) * 0.95))]
}
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func loadSamples(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = file.processingFormat
    guard format.sampleRate == 16000, format.channelCount == 1 else {
        fatalError("expected 16 kHz mono: \(path) got \(format.sampleRate) x \(format.channelCount)")
    }
    guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        fatalError("alloc")
    }
    try file.read(into: buf)
    guard let ch = buf.floatChannelData else { fatalError("no data") }
    return Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
}

func units(_ s: String) -> MLComputeUnits {
    switch s {
    case "gpu": return .cpuAndGPU
    case "cpu": return .cpuOnly
    case "all": return .all
    default: return .cpuAndNeuralEngine
    }
}

func load(_ dir: URL, _ name: String, _ u: MLComputeUnits) throws -> MLModel {
    let cfg = MLModelConfiguration()
    cfg.computeUnits = u
    return try MLModel(contentsOf: dir.appendingPathComponent("\(name).mlmodelc"), configuration: cfg)
}

// Synthetic zero-filled inputs matching the model's declared shapes.
func zeroInputs(_ model: MLModel) throws -> MLDictionaryFeatureProvider {
    var dict: [String: Any] = [:]
    for (name, desc) in model.modelDescription.inputDescriptionsByName {
        guard let c = desc.multiArrayConstraint else { continue }
        // A range-shaped input (the mobius preprocessor) is exercised at its maximum size.
        var shape = c.shape
        if c.shapeConstraint.type == .range {
            shape = (0..<c.shape.count).map { d in
                let r = c.shapeConstraint.sizeRangeForDimension[d].rangeValue
                return NSNumber(value: r.location + r.length - 1)
            }
        }
        let arr = try MLMultiArray(shape: shape, dataType: c.dataType)
        let n = arr.count
        let ptr = arr.dataPointer
        let audioLength = Int32(shape.last?.intValue ?? 240000)
        switch c.dataType {
        case .int32:
            // decoder targets: use blank id 8192 as a plausible token
            let p = ptr.bindMemory(to: Int32.self, capacity: n)
            for i in 0..<n { p[i] = name.contains("length") ? (shape.count == 1 ? audioLength : 1) : 8192 }
        case .float32:
            let p = ptr.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { p[i] = 0 }
        case .float16:
            memset(ptr, 0, n * 2)
        default:
            memset(ptr, 0, n * 4)
        }
        dict[name] = MLFeatureValue(multiArray: arr)
    }
    return try MLDictionaryFeatureProvider(dictionary: dict)
}

func describe(_ model: MLModel, _ label: String) {
    var ins: [String] = []
    for (name, desc) in model.modelDescription.inputDescriptionsByName.sorted(by: { $0.key < $1.key }) {
        if let c = desc.multiArrayConstraint {
            let flex = c.shapeConstraint.type == .range ? " (range)" : ""
            ins.append("\(name)\(c.shape.map { $0.intValue })/\(c.dataType.rawValue)\(flex)")
        }
    }
    var outs: [String] = []
    for (name, desc) in model.modelDescription.outputDescriptionsByName.sorted(by: { $0.key < $1.key }) {
        if let c = desc.multiArrayConstraint { outs.append("\(name)\(c.shape.map { $0.intValue })") } else { outs.append(name) }
    }
    print("\(label): in \(ins.joined(separator: " ")) | out \(outs.joined(separator: " "))")
}

func timeModel(_ model: MLModel, warm: Int, runs: Int) throws -> (Double, Double) {
    let input = try zeroInputs(model)
    for _ in 0..<warm { _ = try model.prediction(from: input) }
    var t: [Double] = []
    for _ in 0..<runs {
        let a = now()
        _ = try model.prediction(from: input)
        t.append(now() - a)
    }
    return (median(t), p95(t))
}

let dir = URL(fileURLWithPath: arg("--dir", ""))
let encUnits = arg("--encoder-units", "ane")
let decUnits = arg("--decoder-units", "ane")
let runs = Int(arg("--runs", "20")) ?? 20
let audioArgs = CommandLine.arguments.enumerated().filter { $0.element == "--audio" }.map { CommandLine.arguments[$0.offset + 1] }
guard !dir.path.isEmpty else { fatalError("--dir required") }

print("bundle: \(dir.path)")
print("encoder units: \(encUnits) decoder/joint units: \(decUnits)")

let t0 = now()
let pre = try load(dir, "Preprocessor", .cpuOnly)
let enc = try load(dir, "Encoder", units(encUnits))
let dec = try load(dir, "Decoder", units(decUnits))
let joint = try load(dir, "JointDecisionv3", units(decUnits))
print(String(format: "load all: %.0f ms", now() - t0))

describe(pre, "Preprocessor")
describe(enc, "Encoder")
describe(dec, "Decoder")
describe(joint, "Joint")

if flag("--components") {
    let (pm, pp) = try timeModel(pre, warm: 3, runs: runs)
    print(String(format: "Preprocessor (cpu)         p50 %.2f ms  p95 %.2f ms", pm, pp))
    let (em, ep) = try timeModel(enc, warm: 3, runs: runs)
    print(String(format: "Encoder (%@)               p50 %.2f ms  p95 %.2f ms", encUnits, em, ep))
    let (dm, dp) = try timeModel(dec, warm: 20, runs: 300)
    print(String(format: "Decoder step (%@)          p50 %.3f ms  p95 %.3f ms", decUnits, dm, dp))
    let (jm, jp) = try timeModel(joint, warm: 20, runs: 300)
    print(String(format: "Joint step (%@)            p50 %.3f ms  p95 %.3f ms", decUnits, jm, jp))
}



if flag("--reset-bench") {
    // Reproduces FluidAudio 0.15.5 MLArrayCache.returnArray -> MLMultiArray.resetData(to: 0):
    // an NSNumber subscript store per element over the 240000-sample preprocessor input buffer.
    let arr = try MLMultiArray(shape: [1, 240000], dataType: .float32)
    var tNS: [Double] = [], tMemset: [Double] = []
    let zero: NSNumber = 0
    for _ in 0..<12 {
        let a = now()
        for i in 0..<arr.count { arr[i] = zero }
        tNS.append(now() - a)
        let b = now()
        memset(arr.dataPointer, 0, arr.count * 4)
        tMemset.append(now() - b)
    }
    tNS.removeFirst(2); tMemset.removeFirst(2)
    print(String(format: "resetData NSNumber loop over 240000: p50 %.2f ms | memset: p50 %.4f ms", median(tNS), median(tMemset)))
    exit(0)
}

if flag("--ideal") {
    // Hand-rolled pipeline: pad to 15 s, preprocessor, encoder, then one joint call per encoder
    // frame with a zero decoder vector. Upper bound on model compute with zero tokens emitted.
    let path = audioArgs.first ?? ""
    let samples = try loadSamples(path)
    let audio = try MLMultiArray(shape: [1, 240000], dataType: .float32)
    let ap = audio.dataPointer.bindMemory(to: Float.self, capacity: 240000)
    for i in 0..<240000 { ap[i] = i < samples.count ? samples[i] : 0 }
    let alen = try MLMultiArray(shape: [1], dataType: .int32)
    alen[0] = NSNumber(value: Int32(samples.count))
    let preIn = try MLDictionaryFeatureProvider(dictionary: ["audio_signal": audio, "audio_length": alen])
    let decStep = try MLMultiArray(shape: [1, 640, 1], dataType: .float32)
    memset(decStep.dataPointer, 0, 640 * 4)
    var tPre: [Double] = [], tEnc: [Double] = [], tJoint: [Double] = [], frames = 0
    for _ in 0..<(3 + runs) {
        var a = now()
        let pre = try pre.prediction(from: preIn)
        let b = now(); tPre.append(b - a)
        let encIn = try MLDictionaryFeatureProvider(dictionary: [
            "mel": pre.featureValue(for: "mel")!, "mel_length": pre.featureValue(for: "mel_length")!])
        a = now()
        let encOut = try enc.prediction(from: encIn)
        tEnc.append(now() - a)
        let encArr = encOut.featureValue(for: "encoder")!.multiArrayValue!
        let n = Int(truncating: encOut.featureValue(for: "encoder_length")!.multiArrayValue![0])
        frames = n
        let step = try MLMultiArray(shape: [1, 1024, 1], dataType: .float32)
        let sp = step.dataPointer.bindMemory(to: Float.self, capacity: 1024)
        let ep = encArr.dataPointer.bindMemory(to: Float.self, capacity: encArr.count)
        let stride = encArr.strides[1].intValue
        a = now()
        for f in 0..<n {
            for h in 0..<1024 { sp[h] = ep[h * stride + f] }
            let jin = try MLDictionaryFeatureProvider(dictionary: ["encoder_step": step, "decoder_step": decStep])
            _ = try joint.prediction(from: jin)
        }
        tJoint.append(now() - a)
    }
    tPre.removeFirst(3); tEnc.removeFirst(3); tJoint.removeFirst(3)
    print(String(format: "IDEAL %@: frames %d | pre p50 %.2f | enc p50 %.2f | joint x%d p50 %.2f (%.3f/call) | sum %.2f ms",
                 (path as NSString).lastPathComponent, frames, median(tPre), median(tEnc), frames, median(tJoint),
                 median(tJoint) / Double(max(frames, 1)), median(tPre) + median(tEnc) + median(tJoint)))
    exit(0)
}

if !audioArgs.isEmpty {
    let vocabData = try Data(contentsOf: dir.appendingPathComponent("parakeet_vocab.json"))
    let raw = try JSONDecoder().decode([String: String].self, from: vocabData)
    var vocab: [Int: String] = [:]
    for (k, v) in raw { if let id = Int(k) { vocab[id] = v } }
    let cfg = MLModelConfiguration()
    cfg.computeUnits = .cpuAndNeuralEngine
    let models = AsrModels(encoder: enc, preprocessor: pre, decoder: dec, joint: joint,
                           configuration: cfg, vocabulary: vocab, version: .v3)
    let manager = AsrManager(config: .default, models: models)
    let layers = await manager.decoderLayerCount
    for path in audioArgs {
        let samples = try loadSamples(path)
        var text = ""
        var tokens = 0
        for _ in 0..<3 {
            var st = TdtDecoderState.make(decoderLayers: layers)
            _ = try await manager.transcribe(samples, decoderState: &st)
        }
        var times: [Double] = []
        var reported: [Double] = []
        for _ in 0..<runs {
            var st = TdtDecoderState.make(decoderLayers: layers)
            let a = now()
            let r = try await manager.transcribe(samples, decoderState: &st)
            times.append(now() - a)
            reported.append(r.processingTime * 1000)
            text = r.text
            tokens = r.text.split(separator: " ").count
        }
        let secs = Double(samples.count) / 16000
        print(String(format: "%@ (%.2f s): wall p50 %.2f ms p95 %.2f ms | reported p50 %.2f ms | words %d | rtfx %.0f",
                     (path as NSString).lastPathComponent, secs, median(times), p95(times), median(reported), tokens, secs * 1000 / median(times)))
        print("  text: \(text)")
    }
}
