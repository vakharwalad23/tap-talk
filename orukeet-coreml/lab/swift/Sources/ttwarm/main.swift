// Picks the faster Encoder placement (Neural Engine vs GPU) for a compiled bundle, and measures
// the one-time Neural Engine program build cost on a freshly compiled model. Reads input names
// and shapes from the model description, so it works on any bundle's Encoder.mlmodelc.
@preconcurrency import CoreML
import Foundation

func arg(_ name: String, _ def: String) -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return def
}

func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func fail(_ message: String) -> Never {
    note(message)
    exit(1)
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

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

func loadTimed(_ path: URL, _ units: MLComputeUnits) throws -> (MLModel, Double) {
    let cfg = MLModelConfiguration()
    cfg.computeUnits = units
    let start = now()
    let model = try MLModel(contentsOf: path, configuration: cfg)
    return (model, now() - start)
}

struct SyntheticInput {
    let provider: MLDictionaryFeatureProvider
    let summary: String
}

// A rank-1 int32 field named like "length" describes another input's time axis; fill it with
// that axis size, not zero, so the call looks like a full sequence rather than an empty one.
func zeroInputs(_ model: MLModel) throws -> SyntheticInput {
    struct Field { let name: String; let shape: [NSNumber]; let dataType: MLMultiArrayDataType }
    var fields: [Field] = []
    for (name, desc) in model.modelDescription.inputDescriptionsByName.sorted(by: { $0.key < $1.key }) {
        guard let c = desc.multiArrayConstraint else { continue }
        var shape = c.shape
        if c.shapeConstraint.type == .range {
            shape = (0..<c.shape.count).map { d in
                let r = c.shapeConstraint.sizeRangeForDimension[d].rangeValue
                return NSNumber(value: r.location + r.length - 1)
            }
        }
        fields.append(Field(name: name, shape: shape, dataType: c.dataType))
    }
    let timeDim = fields.filter { $0.shape.count > 1 }.compactMap { $0.shape.last?.intValue }.max() ?? 1

    var dict: [String: Any] = [:]
    var parts: [String] = []
    for field in fields {
        let arr = try MLMultiArray(shape: field.shape, dataType: field.dataType)
        let n = arr.count
        let ptr = arr.dataPointer
        let isLength = field.shape.count == 1 && field.name.contains("length")
        switch field.dataType {
        case .int32:
            let p = ptr.bindMemory(to: Int32.self, capacity: n)
            let value = Int32(isLength ? timeDim : 0)
            for i in 0..<n { p[i] = value }
        case .float32:
            let p = ptr.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { p[i] = 0 }
        case .float16:
            memset(ptr, 0, n * 2)
        default:
            memset(ptr, 0, n * 4)
        }
        dict[field.name] = MLFeatureValue(multiArray: arr)
        let shapeDesc = field.shape.map { $0.intValue }
        parts.append(isLength ? "\(field.name)\(shapeDesc)=\(timeDim)" : "\(field.name)\(shapeDesc)")
    }
    let provider = try MLDictionaryFeatureProvider(dictionary: dict)
    return SyntheticInput(provider: provider, summary: parts.joined(separator: " "))
}

func timeRuns(_ model: MLModel, _ input: MLFeatureProvider, warm: Int, runs: Int) throws -> (Double, Double) {
    for _ in 0..<warm { _ = try model.prediction(from: input) }
    var t: [Double] = []
    for _ in 0..<runs {
        let start = now()
        _ = try model.prediction(from: input)
        t.append(now() - start)
    }
    return (median(t), p95(t))
}

// Loads the encoder once per compute unit and times N predictions on each; lower median wins.
func runPlacementPick(dir: URL, runs: Int) throws {
    let path = dir.appendingPathComponent("Encoder.mlmodelc")
    let (aneModel, aneLoadMs) = try loadTimed(path, .cpuAndNeuralEngine)
    let (gpuModel, gpuLoadMs) = try loadTimed(path, .cpuAndGPU)

    let input = try zeroInputs(aneModel)
    note("encoder: \(path.path)")
    note("synthetic input: \(input.summary)")

    let (aneMedian, aneP95) = try timeRuns(aneModel, input.provider, warm: 3, runs: runs)
    let (gpuMedian, gpuP95) = try timeRuns(gpuModel, input.provider, warm: 3, runs: runs)

    note(String(format: "ane load %.1f ms | median %.2f ms p95 %.2f ms over %d runs", aneLoadMs, aneMedian, aneP95, runs))
    note(String(format: "gpu load %.1f ms | median %.2f ms p95 %.2f ms over %d runs", gpuLoadMs, gpuMedian, gpuP95, runs))
    let chosen = aneMedian <= gpuMedian ? "ane" : "gpu"
    note("pick: \(chosen) (lower median)")

    // Built by hand instead of through JSONEncoder, whose key order for this struct did not
    // match declaration order on this toolchain; every value here is a number this process
    // computed or one of the two fixed placement literals, so there is no escaping to get wrong.
    let line = String(
        format: "{\"encoder_units\":\"%@\",\"ane_ms\":%.2f,\"gpu_ms\":%.2f,\"ane_load_ms\":%.2f,\"gpu_load_ms\":%.2f,\"runs\":%d}",
        chosen, aneMedian, gpuMedian, aneLoadMs, gpuLoadMs, runs)
    print(line)
}

// Compares a first MLModel instance's load and predict time against a second instance built
// from the same freshly compiled path, which still hits the Neural Engine's cache if one exists.
func runFirstLoad(package: URL) throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ttwarm-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer {
        do { try FileManager.default.removeItem(at: tmp) }
        catch { note("warning: could not remove temp dir \(tmp.path): \(error)") }
    }

    note("compiling \(package.lastPathComponent) into \(tmp.path)")
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["coremlcompiler", "compile", package.path, tmp.path]
    compiler.standardOutput = FileHandle.standardError
    compiler.standardError = FileHandle.standardError
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else {
        fail("coremlcompiler exited with status \(compiler.terminationStatus)")
    }

    let entries = try FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
    guard let compiled = entries.first(where: { $0.pathExtension == "mlmodelc" }) else {
        fail("coremlcompiler produced no .mlmodelc in \(tmp.path)")
    }

    let cfg = MLModelConfiguration()
    cfg.computeUnits = .cpuAndNeuralEngine

    let firstLoadStart = now()
    let firstModel = try MLModel(contentsOf: compiled, configuration: cfg)
    let firstLoadMs = now() - firstLoadStart
    let input = try zeroInputs(firstModel)
    let firstPredictStart = now()
    _ = try firstModel.prediction(from: input.provider)
    let firstPredictMs = now() - firstPredictStart

    let warmLoadStart = now()
    let warmModel = try MLModel(contentsOf: compiled, configuration: cfg)
    let warmLoadMs = now() - warmLoadStart
    let warmPredictStart = now()
    _ = try warmModel.prediction(from: input.provider)
    let warmPredictMs = now() - warmPredictStart

    note("compiled to \(compiled.lastPathComponent), input \(input.summary)")
    print(String(format: "first load %.1f ms + predict %.1f ms = %.1f ms", firstLoadMs, firstPredictMs, firstLoadMs + firstPredictMs))
    print(String(format: "warm  load %.1f ms + predict %.1f ms = %.1f ms", warmLoadMs, warmPredictMs, warmLoadMs + warmPredictMs))
    print("the neural engine program cache is keyed by model content, not by file path or process.")
    print("a model recompiled from the same source can still land in a warm cache on what this")
    print("process sees as its first load; this tool does not know, and does not claim to know,")
    print("where that cache is stored on disk.")
}

let firstLoadArg = arg("--first-load", "")
let dirArg = arg("--dir", "")

if !firstLoadArg.isEmpty {
    try runFirstLoad(package: URL(fileURLWithPath: firstLoadArg))
} else if !dirArg.isEmpty {
    let runs = Int(arg("--runs", "10")) ?? 10
    try runPlacementPick(dir: URL(fileURLWithPath: dirArg), runs: runs)
} else {
    fail("usage: ttwarm --dir <bundle> [--runs N] | ttwarm --first-load <Encoder.mlpackage>")
}
