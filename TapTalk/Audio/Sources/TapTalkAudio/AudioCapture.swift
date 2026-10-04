import AVFoundation

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
    // Recursive: AVAudioEngine may post its configuration change synchronously from inside start().
    private let lock = NSRecursiveLock()
    private var sink: AVAudioSinkNode?
    private var ring: SampleRing?
    private var sampleRate: Double = 0
    private var needsRebuild = true
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
            needsRebuild = true
        }
    }

    private func buildIfNeeded() throws {
        guard needsRebuild else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        if let sink {
            engine.disconnectNodeInput(sink)
            engine.detach(sink)
            self.sink = nil
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInputDevice }
        let ring = SampleRing(capacity: Int(format.sampleRate * Self.ringSeconds))
        let writer = ring.writer
        let node = AVAudioSinkNode { _, frames, list in
            writer.writeDownmix(list, frames: Int(frames))
            return noErr
        }
        engine.attach(node)
        engine.connect(input, to: node, format: format)
        engine.prepare()
        observeConfigurationChanges()
        sink = node
        self.ring = ring
        sampleRate = format.sampleRate
        needsRebuild = false
    }

    // A device change stops the engine; the next start rebuilds the graph for the new format.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.needsRebuild = true }
        }
    }
}
