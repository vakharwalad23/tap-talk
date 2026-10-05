import AVFoundation
import os

/// A started capture: the ring the session's samples land in, and the first sample that is theirs.
public struct CaptureSession: Sendable {
    public let ring: SampleRing
    public let sampleRate: Double
    public let startMark: Int64

    public init(ring: SampleRing, sampleRate: Double, startMark: Int64) {
        self.ring = ring
        self.sampleRate = sampleRate
        self.startMark = startMark
    }
}

/// Source of mono microphone samples for a dictation.
public protocol AudioCapture: AnyObject, Sendable {
    /// Builds the graph ahead of the first recording so device setup happens at launch.
    func prepare() throws
    /// Starts delivering samples and returns where they land.
    func start() throws -> CaptureSession
    /// Stops delivery and releases the device; the graph stays built for the next start.
    func pause()
    /// Stops for good; used on app quit.
    func shutdown()
}

/// AVAudioEngine input into an AVAudioSinkNode whose real-time block only downmixes into the ring.
// Unchecked: every engine, graph and ring access below holds `lock`.
public final class MicrophoneCapture: AudioCapture, @unchecked Sendable {
    // 4 s at the device rate; the pump drains every 32 ms, so this only fills if it stalls for seconds.
    private static let ringSeconds = 4.0

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let rebuild = RebuildFlag()
    private var sink: AVAudioSinkNode?
    private var ring: SampleRing?
    private var sampleRate: Double = 0
    private var configurationObserver: NSObjectProtocol?

    public init() {}

    deinit {
        shutdown()
    }

    public func prepare() throws {
        try lock.withLock { try buildIfNeeded() }
    }

    public func start() throws -> CaptureSession {
        try lock.withLock {
            try buildIfNeeded()
            guard let ring else { throw AudioCaptureError.noInputDevice }
            let mark = ring.writtenCount
            do {
                try engine.start()
            } catch {
                // A start that fails on a stale graph must not fail forever; the next start rebuilds it.
                rebuild.markStale()
                throw AudioCaptureError.engineStart(error.localizedDescription)
            }
            return CaptureSession(ring: ring, sampleRate: sampleRate, startMark: mark)
        }
    }

    public func pause() {
        lock.withLock { engine.pause() }
    }

    public func shutdown() {
        lock.withLock {
            engine.stop()
            if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
            configurationObserver = nil
            rebuild.markStale()
        }
    }

    // Marks only the flag, never `lock`: AVAudioEngine can post this while start() or pause() hold it.
    static func observeConfigurationChanges(of engine: AVAudioEngine, marking flag: RebuildFlag) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { _ in
            flag.markStale()
        }
    }

    private func buildIfNeeded() throws {
        guard rebuild.claim() else { return }
        do {
            try build()
        } catch {
            rebuild.markStale()
            throw error
        }
    }

    private func build() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        if let sink {
            // Rewiring a running or half-reset engine raises an Objective-C exception; stop it first.
            engine.stop()
            engine.disconnectNodeInput(sink)
            engine.detach(sink)
            self.sink = nil
        }
        let input = engine.inputNode
        // The hardware side: after a device change the output side keeps the old device's format, and connecting with it throws.
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInputDevice }
        guard format.isStandard else { throw AudioCaptureError.unsupportedFormat(format.sampleRate) }
        let ring = SampleRing(capacity: Int(format.sampleRate * Self.ringSeconds))
        let writer = ring.writer
        let node = AVAudioSinkNode { _, frames, list in
            writer.writeDownmix(list, frames: Int(frames))
            return noErr
        }
        engine.attach(node)
        engine.connect(input, to: node, format: format)
        engine.prepare()
        if configurationObserver == nil {
            configurationObserver = Self.observeConfigurationChanges(of: engine, marking: rebuild)
        }
        sink = node
        self.ring = ring
        sampleRate = format.sampleRate
    }
}

/// Whether the audio graph must be rebuilt before the next start; any thread may mark it.
struct RebuildFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: true)

    /// True when a rebuild is due; clears the mark so a change during the rebuild marks it again.
    func claim() -> Bool {
        state.withLock { due in
            defer { due = false }
            return due
        }
    }

    func markStale() {
        state.withLock { $0 = true }
    }
}
