import AVFoundation
import CoreAudio

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
    /// Attaches to the microphone ahead of the first recording so device setup happens at launch.
    func prepare() throws
    /// Starts delivering samples and returns where they land.
    func start() throws -> CaptureSession
    /// Stops delivery and releases the device; stays attached for the next start.
    func pause()
    /// Stops for good; used on app quit.
    func shutdown()
}

/// Core Audio IOProc on the chosen input device; the real-time block only downmixes into the ring.
// AVAudioEngine is not used: its input node records through a per-process aggregate of the default
// input and output, which pulls Bluetooth headphones into headset mode at launch and overrides
// kAudioOutputUnitProperty_CurrentDevice about 300 ms after it is set.
// Unchecked: every device, IOProc and ring access below holds `lock`.
public final class MicrophoneCapture: AudioCapture, @unchecked Sendable {
    // 4 s at the device rate; the pump drains every 32 ms, so this only fills if it stalls for seconds.
    private static let ringSeconds = 4.0

    private let lock = NSLock()
    private var device = kAudioObjectUnknown
    private var procID: AudioDeviceIOProcID?
    private var ring: SampleRing?
    private var sampleRate: Double = 0

    public init() {}

    deinit {
        shutdown()
    }

    public func prepare() throws {
        try lock.withLock { try attach() }
    }

    public func start() throws -> CaptureSession {
        try lock.withLock {
            try attach()
            guard let procID, let ring else { throw AudioCaptureError.noInputDevice }
            let mark = ring.writtenCount
            let status = AudioDeviceStart(device, procID)
            guard status == noErr else {
                // A device that refuses to start is reattached from scratch on the next press.
                detach()
                throw AudioCaptureError.engineStart("OSStatus \(status)")
            }
            return CaptureSession(ring: ring, sampleRate: sampleRate, startMark: mark)
        }
    }

    public func pause() {
        lock.withLock {
            if let procID { AudioDeviceStop(device, procID) }
        }
    }

    public func shutdown() {
        lock.withLock { detach() }
    }

    // Re-resolved on every start, so a changed default input, a closed lid or a vanished device
    // takes effect on the next press without listening for device notifications.
    private func attach() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        guard let target = MicrophoneSelection.currentDevice(),
              let format = MicrophoneSelection.inputFormat(of: target) else {
            detach()
            throw AudioCaptureError.noInputDevice
        }
        if target == device, procID != nil, format.mSampleRate == sampleRate { return }
        detach()
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
            throw AudioCaptureError.unsupportedFormat(format.mSampleRate)
        }
        let ring = SampleRing(capacity: Int(format.mSampleRate * Self.ringSeconds))
        let writer = ring.writer
        var id: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&id, target, nil) { _, input, _, _, _ in
            let first = input.pointee.mBuffers
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(1, Int(first.mNumberChannels)))
            writer.writeDownmix(input, frames: frames)
        }
        guard status == noErr, let id else { throw AudioCaptureError.engineStart("OSStatus \(status)") }
        device = target
        procID = id
        self.ring = ring
        sampleRate = format.mSampleRate
    }

    // Stop before destroy: the ring the IOProc writes into must outlive its last callback.
    private func detach() {
        if let procID {
            AudioDeviceStop(device, procID)
            AudioDeviceDestroyIOProcID(device, procID)
        }
        procID = nil
        device = kAudioObjectUnknown
    }
}
