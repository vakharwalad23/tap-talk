// TapTalk-side TDT decode without FluidAudio. Runs a compiled bundle (Preprocessor, Encoder,
// Decoder, JointDecisionv3) with FluidAudio's single-window decode semantics, so transcripts match
// AsrManager.transcribe while the pipeline stays open to what FluidAudio cannot do: an encoder
// window picked per clip, a fused decoder+joint graph, per-token confidences. Writes hypotheses
// for bench/score.py and per-stage timings. A K-frame batched joint keeps the older NeMo-style
// loop as a measurement path.
@preconcurrency import CoreML
import AVFoundation
import Foundation

let blankId = 8192
let hiddenSize = 1024
let decoderHidden = 640
let samplesPerFrame = 1280
let sampleRate = 16000
let durationBins = [0, 1, 2, 3, 4]
// FluidAudio TdtConfig defaults.
let maxSymbolsPerStep = 10
let consecutiveBlankLimit = 5
let maxTokensPerChunk = 150
// FluidAudio empty-decode recovery (its issue #910).
let recoveryMinimumSamples = 2 * sampleRate
let recoveryMinimumRMS: Float = 0.003
let recoveryMinimumConfidence: Float = 0.7
let recoveryMinimumTokens = 2
let trimmedTailSamples = sampleRate / 5
// Legacy batched loop.
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
    let confidence: Float
    let window: Double
}

struct Timing {
    var preprocessorMs = 0.0
    var encoderMs = 0.0
    var decodeMs = 0.0
    var decoderCalls = 0
    var jointCalls = 0
    var tokens = 0
    var retries = 0
    var windowSeconds = 0.0
    var totalMs: Double { preprocessorMs + encoderMs + decodeMs }

    mutating func add(_ other: Timing) {
        preprocessorMs += other.preprocessorMs
        encoderMs += other.encoderMs
        decodeMs += other.decodeMs
        decoderCalls += other.decoderCalls
        jointCalls += other.jointCalls
        tokens += other.tokens
        retries += other.retries
    }
}

struct Hypothesis {
    var tokens: [Int] = []
    var confidences: [Float] = []
    var meanConfidence: Float { confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count) }
    var minConfidence: Float { confidences.min() ?? 0 }
}

struct LengthPolicy: OptionSet {
    let rawValue: Int
    static let encoderFull = LengthPolicy(rawValue: 1)
    static let preprocessorFull = LengthPolicy(rawValue: 2)
    static let trimmedTail = LengthPolicy(rawValue: 4)
}

let recoveryPolicies: [LengthPolicy] = [
    .encoderFull, .preprocessorFull, .trimmedTail, [.trimmedTail, .encoderFull], [.trimmedTail, .preprocessorFull],
]

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
    return nil
}

func args(_ name: String) -> [String] {
    let a = CommandLine.arguments
    return a.enumerated().filter { $0.element == name && $0.offset + 1 < a.count }.map { a[$0.offset + 1] }
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

func zeroState() throws -> MLMultiArray {
    let state = try MLMultiArray(shape: [2, 1, NSNumber(value: decoderHidden)], dataType: .float32)
    memset(state.dataPointer, 0, state.count * MemoryLayout<Float>.stride)
    return state
}

func feature(_ provider: MLFeatureProvider, _ name: String) -> MLMultiArray {
    guard let value = provider.featureValue(for: name)?.multiArrayValue else { fail("model output \(name) missing") }
    return value
}

// One preprocessor + encoder pair with a fixed audio window, plus its reused input buffers.
final class Window {
    let samples: Int
    let preprocessor: MLModel
    let encoder: MLModel
    let audio: MLMultiArray
    let audioLength: MLMultiArray
    var seconds: Double { Double(samples) / Double(sampleRate) }

    init(dir: URL, encoderUnits: MLComputeUnits) throws {
        preprocessor = try loadModel(dir.appendingPathComponent("Preprocessor.mlmodelc"), .cpuOnly)
        encoder = try loadModel(dir.appendingPathComponent("Encoder.mlmodelc"), encoderUnits)
        guard let shape = preprocessor.modelDescription.inputDescriptionsByName["audio_signal"]?.multiArrayConstraint?.shape,
              shape.count == 2 else {
            fail("preprocessor in \(dir.lastPathComponent) has no fixed audio_signal [1, N] input")
        }
        samples = shape[1].intValue
        audio = try MLMultiArray(shape: [1, NSNumber(value: samples)], dataType: .float32)
        audioLength = try MLMultiArray(shape: [1], dataType: .int32)
    }
}

// Copies one encoder frame [1024] into a [1, 1024, 1] joint input.
struct FrameSource {
    let base: UnsafeMutablePointer<Float>
    let hiddenStride: Int
    let timeStride: Int

    init(_ encoderOut: MLMultiArray) {
        base = encoderOut.dataPointer.bindMemory(to: Float.self, capacity: encoderOut.count)
        hiddenStride = encoderOut.strides[1].intValue
        timeStride = encoderOut.strides[2].intValue
    }

    func copy(frame t: Int, into step: MLMultiArray) {
        let dst = step.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize)
        let src = base.advanced(by: t * timeStride)
        for h in 0..<hiddenSize { dst[h] = src[h * hiddenStride] }
    }
}

struct Decision {
    let token: Int
    let probability: Float
    let durationBin: Int
}

// The decoder side of one joint step. `score` predicts at a frame from the current predictor
// context; `emit` consumes a token so the next `score` sees it.
protocol Stepper: AnyObject {
    func reset(timing: inout Timing) throws
    func attach(_ encoderOut: MLMultiArray)
    func score(frame: Int, timing: inout Timing) throws -> Decision
    func emit(_ token: Int, timing: inout Timing) throws
}

func readDecision(_ output: MLFeatureProvider) -> Decision {
    Decision(token: Int(truncating: feature(output, "token_id")[0]),
             probability: feature(output, "token_prob")[0].floatValue,
             durationBin: Int(truncating: feature(output, "duration")[0]))
}

// Shipped graphs: Decoder (LSTM + projection, run once per emitted token, projection cached) and
// the single-step joint. Mirrors FluidAudio's predictorOutput cache.
final class SeparateStepper: Stepper {
    let decoder: MLModel
    let joint: MLModel
    let targets: MLMultiArray
    let targetLength: MLMultiArray
    let encoderStep: MLMultiArray
    var h: MLMultiArray
    var c: MLMultiArray
    var projection: MLMultiArray?
    var frames: FrameSource?

    init(decoder: MLModel, joint: MLModel) throws {
        self.decoder = decoder
        self.joint = joint
        targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
        targetLength = try MLMultiArray(shape: [1], dataType: .int32)
        targetLength[0] = 1
        encoderStep = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize), 1], dataType: .float32)
        h = try zeroState()
        c = try zeroState()
    }

    func reset(timing: inout Timing) throws {
        h = try zeroState()
        c = try zeroState()
        try runDecoder(blankId, timing: &timing)
    }

    func attach(_ encoderOut: MLMultiArray) { frames = FrameSource(encoderOut) }

    private func runDecoder(_ token: Int, timing: inout Timing) throws {
        targets[0] = NSNumber(value: Int32(token))
        timing.decoderCalls += 1
        let output = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "targets": targets, "target_length": targetLength, "h_in": h, "c_in": c]))
        projection = feature(output, "decoder")
        h = feature(output, "h_out")
        c = feature(output, "c_out")
    }

    func score(frame: Int, timing: inout Timing) throws -> Decision {
        guard let frames, let projection else { fail("stepper used before reset/attach") }
        frames.copy(frame: frame, into: encoderStep)
        timing.jointCalls += 1
        let output = try joint.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "encoder_step": encoderStep, "decoder_step": projection]))
        return readDecision(output)
    }

    func emit(_ token: Int, timing: inout Timing) throws {
        try runDecoder(token, timing: &timing)
    }
}

// Fused decoder+joint graph (mobius fuse_decoder_joint.py): every step recomputes the LSTM for
// the last emitted token from the state before it, so one dispatch replaces decoder and joint.
final class FusedStepper: Stepper {
    let model: MLModel
    let targets: MLMultiArray
    let targetLength: MLMultiArray
    let encoderStep: MLMultiArray
    var hIn: MLMultiArray
    var cIn: MLMultiArray
    var hOut: MLMultiArray?
    var cOut: MLMultiArray?
    var lastToken = blankId
    var frames: FrameSource?

    init(model: MLModel) throws {
        self.model = model
        targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
        targetLength = try MLMultiArray(shape: [1], dataType: .int32)
        targetLength[0] = 1
        encoderStep = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize), 1], dataType: .float32)
        hIn = try zeroState()
        cIn = try zeroState()
    }

    func reset(timing: inout Timing) throws {
        hIn = try zeroState()
        cIn = try zeroState()
        hOut = nil
        cOut = nil
        lastToken = blankId
    }

    func attach(_ encoderOut: MLMultiArray) { frames = FrameSource(encoderOut) }

    func score(frame: Int, timing: inout Timing) throws -> Decision {
        guard let frames else { fail("stepper used before attach") }
        frames.copy(frame: frame, into: encoderStep)
        targets[0] = NSNumber(value: Int32(lastToken))
        timing.jointCalls += 1
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "targets": targets, "target_length": targetLength, "h_in": hIn, "c_in": cIn, "encoder_step": encoderStep]))
        hOut = feature(output, "h_out")
        cOut = feature(output, "c_out")
        return readDecision(output)
    }

    func emit(_ token: Int, timing: inout Timing) throws {
        guard let hOut, let cOut else { fail("emit before score") }
        hIn = hOut
        cIn = cOut
        lastToken = token
    }
}

func clampProbability(_ value: Float) -> Float {
    guard value.isFinite else { return 0 }
    return max(0, min(1, value))
}

func mapDuration(_ bin: Int) -> Int {
    guard bin >= 0, bin < durationBins.count else { fail("duration bin out of range: \(bin)") }
    return durationBins[bin]
}

// FluidAudio TdtDecoderV3.decodeWithTimings for a single, last chunk: outer joint step, inner
// blank loop on the cached predictor output, same-frame and forced-advance rules, then the
// end-of-window flush over three boundary frames.
func decodeFluid(_ stepper: Stepper, encoderOut: MLMultiArray, encoderLength: Int, actualFrames: Int,
                 timing: inout Timing) throws -> Hypothesis {
    var hypothesis = Hypothesis()
    guard encoderLength > 1 else { return hypothesis }
    let effectiveLength = min(encoderLength, actualFrames)
    let lastTimestep = effectiveLength - 1
    var t = 0
    var safeT = min(t, lastTimestep)
    var active = t < effectiveLength
    guard active else { return hypothesis }

    stepper.attach(encoderOut)
    try stepper.reset(timing: &timing)

    var lastEmissionTimestamp = -1
    var emissionsAtThisTimestamp = 0
    var tokensProcessed = 0
    var emittedAt = t

    while active {
        var decision = try stepper.score(frame: safeT, timing: &timing)
        var label = decision.token
        var duration = mapDuration(decision.durationBin)
        var blank = label == blankId
        if !blank && duration == 0 && t == lastEmissionTimestamp && emissionsAtThisTimestamp >= 1 {
            duration = 1
        }
        if blank && duration == 0 { duration = 1 }
        emittedAt = t
        t += duration
        safeT = min(t, lastTimestep)
        active = t < effectiveLength
        var advance = active && blank

        while advance {
            emittedAt = t
            decision = try stepper.score(frame: safeT, timing: &timing)
            label = decision.token
            duration = mapDuration(decision.durationBin)
            blank = label == blankId
            if blank && duration == 0 { duration = 1 }
            t += duration
            safeT = min(t, lastTimestep)
            active = t < effectiveLength
            advance = active && blank
        }

        if active && label != blankId {
            tokensProcessed += 1
            if tokensProcessed > maxTokensPerChunk { break }
            hypothesis.tokens.append(label)
            hypothesis.confidences.append(clampProbability(decision.probability))
            try stepper.emit(label, timing: &timing)
            if emittedAt == lastEmissionTimestamp {
                emissionsAtThisTimestamp += 1
            } else {
                lastEmissionTimestamp = emittedAt
                emissionsAtThisTimestamp = 1
            }
            if emissionsAtThisTimestamp >= maxSymbolsPerStep {
                t = min(t + 1, lastTimestep)
                safeT = min(t, lastTimestep)
                emissionsAtThisTimestamp = 0
                lastEmissionTimestamp = -1
            }
        }
        active = t < effectiveLength
    }

    // Last-chunk flush: re-score frames at the boundary until blanks or the step cap.
    var additionalSteps = 0
    var consecutiveBlanks = 0
    var finalT = t
    let frameCount = encoderLength
    while additionalSteps < maxSymbolsPerStep && consecutiveBlanks < consecutiveBlankLimit {
        let variations = [
            min(finalT, frameCount - 1),
            min(effectiveLength - 1, frameCount - 1),
            min(max(0, effectiveLength - 2), frameCount - 1),
        ]
        let decision = try stepper.score(frame: variations[additionalSteps % variations.count], timing: &timing)
        let duration = mapDuration(decision.durationBin)
        if decision.token == blankId {
            consecutiveBlanks += 1
        } else {
            consecutiveBlanks = 0
            hypothesis.tokens.append(decision.token)
            hypothesis.confidences.append(clampProbability(decision.probability))
            try stepper.emit(decision.token, timing: &timing)
        }
        finalT = min(finalT + max(1, duration), effectiveLength)
        additionalSteps += 1
    }
    return hypothesis
}

final class Pipeline {
    let windows: [Window]
    let decoder: MLModel
    let joint: MLModel
    let vocabulary: [Int: String]
    let stepper: Stepper
    // Frames scored per joint call: 1 for the shipped single-step graph, K for a batched graph.
    let k: Int
    let encoderInputName: String
    let targets: MLMultiArray
    let targetLength: MLMultiArray
    let encoderSteps: MLMultiArray

    init(bundle: URL, windowDirs: [URL], joint jointURL: URL?, fused fusedURL: URL?, encoderUnits: MLComputeUnits) throws {
        var loaded = [try Window(dir: bundle, encoderUnits: encoderUnits)]
        for dir in windowDirs { loaded.append(try Window(dir: dir, encoderUnits: encoderUnits)) }
        windows = loaded.sorted { $0.samples < $1.samples }
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
        if let fusedURL {
            stepper = try FusedStepper(model: try loadModel(fusedURL, .cpuOnly))
        } else {
            stepper = try SeparateStepper(decoder: decoder, joint: joint)
        }
        targets = try MLMultiArray(shape: [1, 1], dataType: .int32)
        targetLength = try MLMultiArray(shape: [1], dataType: .int32)
        targetLength[0] = 1
        encoderSteps = try MLMultiArray(shape: [1, NSNumber(value: hiddenSize), NSNumber(value: k)], dataType: .float32)
    }

    var largest: Window { windows[windows.count - 1] }

    func transcribe(_ samples: [Float], timing: inout Timing) throws -> Hypothesis {
        // FluidAudio pads to a whole 80 ms frame when that still fits the model window.
        let count = min(samples.count, largest.samples)
        let alignedCandidate = (count + samplesPerFrame - 1) / samplesPerFrame * samplesPerFrame
        let fullLength = alignedCandidate <= largest.samples ? alignedCandidate : count
        guard let window = windows.first(where: { $0.samples >= fullLength }) else { fail("no window fits \(fullLength) samples") }
        timing.windowSeconds = window.seconds

        var hypothesis = try infer(window, samples, count: count, fullLength: fullLength, policy: [], timing: &timing)
        guard hypothesis.tokens.isEmpty, k == 1, shouldRecover(samples, count: count, fullLength: fullLength) else {
            timing.tokens += hypothesis.tokens.count
            return hypothesis
        }
        for policy in recoveryPolicies {
            timing.retries += 1
            let retry = try infer(window, samples, count: count, fullLength: fullLength, policy: policy, timing: &timing)
            if retry.tokens.count >= recoveryMinimumTokens, retry.meanConfidence >= recoveryMinimumConfidence {
                hypothesis = retry
                break
            }
        }
        timing.tokens += hypothesis.tokens.count
        return hypothesis
    }

    private func shouldRecover(_ samples: [Float], count: Int, fullLength: Int) -> Bool {
        let length = min(fullLength, count)
        guard fullLength >= recoveryMinimumSamples else { return false }
        var energy = 0.0
        samples.withUnsafeBufferPointer { buffer in
            for i in 0..<length { energy += Double(buffer[i] * buffer[i]) }
        }
        return (energy / Double(fullLength)).squareRoot() >= Double(recoveryMinimumRMS)
    }

    private func infer(_ window: Window, _ samples: [Float], count: Int, fullLength: Int, policy: LengthPolicy,
                       timing: inout Timing) throws -> Hypothesis {
        var t0 = now()
        let audioPtr = window.audio.dataPointer.bindMemory(to: Float.self, capacity: window.samples)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { audioPtr.update(from: base, count: count) }
        }
        if count < window.samples { audioPtr.advanced(by: count).update(repeating: 0, count: window.samples - count) }

        var effectiveLength = fullLength
        if policy.contains(.trimmedTail) {
            effectiveLength = max(recoveryMinimumSamples, fullLength - trimmedTailSamples) / samplesPerFrame * samplesPerFrame
            if effectiveLength < min(window.samples, fullLength) {
                audioPtr.advanced(by: effectiveLength).update(repeating: 0, count: min(window.samples, fullLength) - effectiveLength)
            }
        }
        let declared = policy.contains(.preprocessorFull) ? window.samples : effectiveLength
        window.audioLength[0] = NSNumber(value: Int32(declared))
        var melProvider = try window.preprocessor.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "audio_signal": window.audio, "audio_length": window.audioLength]))
        if policy.contains(.encoderFull) {
            let mel = feature(melProvider, "mel")
            let fullMelLength = try MLMultiArray(shape: [1], dataType: .int32)
            fullMelLength[0] = NSNumber(value: Int32(truncating: mel.shape[2]))
            melProvider = try MLDictionaryFeatureProvider(dictionary: ["mel": mel, "mel_length": fullMelLength])
        }
        timing.preprocessorMs += now() - t0

        t0 = now()
        let encoded = try window.encoder.prediction(from: melProvider)
        timing.encoderMs += now() - t0
        let encoderOut = feature(encoded, "encoder")
        let encoderLength = Int(truncating: feature(encoded, "encoder_length")[0])
        let actualFrames = (effectiveLength + samplesPerFrame - 1) / samplesPerFrame

        t0 = now()
        let hypothesis: Hypothesis
        if k > 1 {
            hypothesis = Hypothesis(tokens: try decodeBatched(encoderOut, frames: encoderLength, timing: &timing), confidences: [])
        } else {
            hypothesis = try decodeFluid(stepper, encoderOut: encoderOut, encoderLength: encoderLength,
                                         actualFrames: actualFrames, timing: &timing)
        }
        timing.decodeMs += now() - t0
        return hypothesis
    }

    private func runDecoder(token: Int, h: MLMultiArray, c: MLMultiArray, timing: inout Timing) throws -> MLFeatureProvider {
        targets[0] = NSNumber(value: Int32(token))
        timing.decoderCalls += 1
        return try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "targets": targets, "target_length": targetLength, "h_in": h, "c_in": c]))
    }

    // Legacy greedy TDT with NeMo semantics over a K-frame batched joint: argmax token and duration
    // per frame; blank advances by its duration without touching the decoder; a non-blank updates
    // the decoder and re-scores from its frame.
    private func decodeBatched(_ encoderOut: MLMultiArray, frames: Int, timing: inout Timing) throws -> [Int] {
        let encPtr = encoderOut.dataPointer.bindMemory(to: Float.self, capacity: encoderOut.count)
        let hiddenStride = encoderOut.strides[1].intValue
        let timeStride = encoderOut.strides[2].intValue
        let stepPtr = encoderSteps.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize * k)

        var h = try zeroState()
        var c = try zeroState()
        var predicted = try runDecoder(token: blankId, h: h, c: c, timing: &timing)
        var decoderStep = feature(predicted, "decoder")
        var pendingH: MLMultiArray? = feature(predicted, "h_out")
        var pendingC: MLMultiArray? = feature(predicted, "c_out")

        var tokens: [Int] = []
        var t = 0
        var symbolsAtFrame = 0
        while t < frames {
            let block = min(k, frames - t)
            for hIdx in 0..<hiddenSize {
                let src = encPtr.advanced(by: hIdx * hiddenStride + t * timeStride)
                let dst = stepPtr.advanced(by: hIdx * k)
                for j in 0..<block { dst[j] = src[j * timeStride] }
                for j in block..<k { dst[j] = 0 }
            }
            timing.jointCalls += 1
            let decision = try joint.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                encoderInputName: encoderSteps, "decoder_step": decoderStep]))
            let ids = feature(decision, "token_id")
            let durations = feature(decision, "duration")
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
                let hIn = pendingH ?? h
                let cIn = pendingC ?? c
                predicted = try runDecoder(token: token, h: hIn, c: cIn, timing: &timing)
                decoderStep = feature(predicted, "decoder")
                h = hIn
                c = cIn
                pendingH = feature(predicted, "h_out")
                pendingC = feature(predicted, "c_out")
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
    fail("usage: ttdecode --bundle <dir> [--window <dir>]... [--fused <model.mlmodelc>] [--joint <batched.mlmodelc>] [--manifest m.json --out hyps.json] [--audio clip.wav --runs N] [--encoder-units ane|gpu|cpu]")
}
let bundle = URL(fileURLWithPath: bundlePath)
let jointURL = arg("--joint").map { URL(fileURLWithPath: $0) }
let fusedURL = arg("--fused").map { URL(fileURLWithPath: $0) }
let windowDirs = args("--window").map { URL(fileURLWithPath: $0) }
let pipeline = try Pipeline(bundle: bundle, windowDirs: windowDirs, joint: jointURL, fused: fusedURL,
                            encoderUnits: units(arg("--encoder-units") ?? "ane"))
note("bundle \(bundle.lastPathComponent), windows \(pipeline.windows.map { String(format: "%.0f s", $0.seconds) }.joined(separator: ", ")), "
     + "decoder \(fusedURL == nil ? "separate" : "fused"), joint \(jointURL?.lastPathComponent ?? "JointDecisionv3.mlmodelc"), K=\(pipeline.k)")

if let manifestPath = arg("--manifest"), let outPath = arg("--out") {
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    let corpusDir = manifestURL.deletingLastPathComponent()
    var rows: [Row] = []
    var total = Timing()
    for fixture in manifest.fixtures {
        let samples = try loadSamples(corpusDir.appendingPathComponent(fixture.path))
        var timing = Timing()
        let hypothesis = try pipeline.transcribe(samples, timing: &timing)
        rows.append(Row(path: fixture.path, sha256: fixture.sha256, language: fixture.language,
                        text: pipeline.text(hypothesis.tokens), ms: timing.totalMs,
                        confidence: hypothesis.meanConfidence, window: timing.windowSeconds))
        total.add(timing)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outURL = URL(fileURLWithPath: outPath)
    try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(rows).write(to: outURL)
    let n = Double(rows.count)
    note(String(format: "wrote %d rows to %@; per clip: pre %.1f enc %.1f decode %.1f ms, %.1f decoder + %.1f joint calls, %.1f tokens, %d retries",
                rows.count, outPath, total.preprocessorMs / n, total.encoderMs / n, total.decodeMs / n,
                Double(total.decoderCalls) / n, Double(total.jointCalls) / n, Double(total.tokens) / n, total.retries))
}

let runs = Int(arg("--runs") ?? "20") ?? 20
for path in args("--audio") {
    let samples = try loadSamples(URL(fileURLWithPath: path))
    var warm = Timing()
    for _ in 0..<3 { _ = try pipeline.transcribe(samples, timing: &warm) }
    var totals: [Double] = []
    var pre: [Double] = []
    var enc: [Double] = []
    var dec: [Double] = []
    var last = Timing()
    var hypothesis = Hypothesis()
    for _ in 0..<runs {
        var timing = Timing()
        hypothesis = try pipeline.transcribe(samples, timing: &timing)
        totals.append(timing.totalMs)
        pre.append(timing.preprocessorMs)
        enc.append(timing.encoderMs)
        dec.append(timing.decodeMs)
        last = timing
    }
    print(String(format: "%@ (%.2f s, window %.0f s): total p50 %.2f ms | pre %.2f | enc %.2f | decode %.2f | %d decoder + %d joint calls, %d tokens, confidence mean %.3f min %.3f, %d retries, K=%d",
                 (path as NSString).lastPathComponent, Double(samples.count) / Double(sampleRate), last.windowSeconds,
                 median(totals), median(pre), median(enc), median(dec), last.decoderCalls, last.jointCalls, last.tokens,
                 hypothesis.meanConfidence, hypothesis.minConfidence, last.retries, pipeline.k))
    print("  text: \(pipeline.text(hypothesis.tokens))")
}
