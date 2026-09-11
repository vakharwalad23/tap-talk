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
let parakeetDir = arg("--parakeet", "models/parakeet/parakeet-tdt-0.6b-v3")
let orukeetDir = arg("--orukeet", "models/orukeet/parakeet-tdt-0.6b-v3")
let outDir = arg("--out", "results")
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let manifestText = try String(contentsOf: URL(fileURLWithPath: manifestPath), encoding: .utf8)
let jsonDecoder = JSONDecoder()
var clips: [Clip] = []
for line in manifestText.split(whereSeparator: \.isNewline) {
    clips.append(try jsonDecoder.decode(Clip.self, from: Data(line.utf8)))
}
guard !clips.isEmpty else { throw BenchError.usage("empty manifest: \(manifestPath)") }
note("loaded \(clips.count) clips from \(manifestPath)")

var samples: [(Clip, [Float])] = []
for c in clips { samples.append((c, try loadSamples(c.audio))) }

// A staging mistake must fail loud, never silently download a model over the network.
ModelHub.offlineMode = true

// Both models load through the identical local-directory path so the comparison is symmetric.
func transcribeAll(_ model: String, _ dir: String, _ items: [(Clip, [Float])]) async throws -> [OutRow] {
    let models = try await AsrModels.load(from: URL(fileURLWithPath: dir), version: .v3)
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    let layers = await manager.decoderLayerCount
    var rows: [OutRow] = []
    for item in items {
        var state = TdtDecoderState.make(decoderLayers: layers)
        let result = try await manager.transcribe(item.1, decoderState: &state)
        rows.append(OutRow(lang: item.0.lang, model: model, ref: item.0.ref, hyp: result.text,
                           ms: result.processingTime * 1000))
    }
    return rows
}

var rows: [OutRow] = []
note("running parakeet")
rows += try await transcribeAll("parakeet", parakeetDir, samples)
note("running orukeet")
rows += try await transcribeAll("orukeet", orukeetDir, samples)

let jsonEncoder = JSONEncoder()
jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try jsonEncoder.encode(rows).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("results.json"))
note("wrote \(rows.count) rows to \(outDir)/results.json")
