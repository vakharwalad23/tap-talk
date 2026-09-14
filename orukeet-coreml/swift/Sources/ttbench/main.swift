import FluidAudio
import Foundation

struct OutRow: Encodable {
    let lang: String
    let model: String
    let ref: String
    let hyp: String
    let ms: Double
}

func arg(_ name: String, _ def: String) -> String {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return def
}

func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

let manifestPath = arg("--manifest", "fleurs/manifest.jsonl")
let modelDir = arg("--model-dir", "")
let label = arg("--label", "")
let outPath = arg("--out", "")
guard !modelDir.isEmpty, !label.isEmpty, !outPath.isEmpty else {
    throw BenchError.usage("need --model-dir, --label, --out")
}
let outURL = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let manifestText = try String(contentsOf: URL(fileURLWithPath: manifestPath), encoding: .utf8)
let jsonDecoder = JSONDecoder()
var clips: [Clip] = []
for line in manifestText.split(whereSeparator: \.isNewline) {
    clips.append(try jsonDecoder.decode(Clip.self, from: Data(line.utf8)))
}
guard !clips.isEmpty else { throw BenchError.usage("empty manifest: \(manifestPath)") }
note("loaded \(clips.count) clips from \(manifestPath)")

// A staging mistake must fail loud, never silently download a model over the network.
ModelHub.offlineMode = true

let models = try await AsrModels.load(from: URL(fileURLWithPath: modelDir), version: .v3)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
let layers = await manager.decoderLayerCount
note("loaded model \(label) from \(modelDir)")

var rows: [OutRow] = []
var done = 0
for clip in clips {
    let samples = try loadSamples(clip.audio)
    var state = TdtDecoderState.make(decoderLayers: layers)
    let result = try await manager.transcribe(samples, decoderState: &state)
    rows.append(OutRow(lang: clip.lang, model: label, ref: clip.ref, hyp: result.text,
                       ms: result.processingTime * 1000))
    done += 1
    if done % 500 == 0 { note("\(label): \(done)/\(clips.count)") }
}

let jsonEncoder = JSONEncoder()
jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try jsonEncoder.encode(rows).write(to: outURL)
note("wrote \(rows.count) rows to \(outPath)")
