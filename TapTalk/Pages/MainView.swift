import SwiftUI

final class RecordingState: ObservableObject {
    enum Phase {
        case idle
        case recording
        case transcribing
        case rewriting
    }

    enum ModelStatus {
        case none
        case loading
        case ready
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelStatus: ModelStatus = .none
    @Published var hotkeyActive = false
    // Accessibility is granted but the tap still cannot be created until TapTalk relaunches.
    @Published var hotkeyNeedsRestart = false
    // False until launch has resolved the engine and the hotkey, so nothing renders a guess.
    @Published private(set) var launchResolved = false
    @Published var status = ""

    @Published private(set) var hotkeyTriggered = false
    @Published private(set) var smartMode = false

    @Published var transcriptText = ""
    @Published var transcriptLang = ""
    @Published var transcriptMs: UInt64 = 0
    @Published var audioDuration: Float = 0

    // Streaming mode: live typing into the focused app. UI shows confirmed + volatile tail.
    @Published var streamingActive = false
    @Published var streamingConfirmed = ""
    @Published var streamingVolatile = ""

    var recording: Bool { phase == .recording }
    var transcribing: Bool { phase == .transcribing }
    var rewriting: Bool { phase == .rewriting }
    var modelReady: Bool { modelStatus == .ready }
    var loadingModel: Bool { modelStatus == .loading }
    // A loading engine still records: transcribe waits for the load to land.
    var canRecord: Bool { modelStatus != .none && phase == .idle }

    func beginRecording(hotkey: Bool, smart: Bool) {
        phase = .recording
        hotkeyTriggered = hotkey
        smartMode = smart
    }

    func beginTranscribing() {
        phase = .transcribing
    }

    func beginRewriting() {
        phase = .rewriting
    }

    func finish() {
        phase = .idle
        smartMode = false
        streamingActive = false
        streamingConfirmed = ""
        streamingVolatile = ""
    }

    func cancel() {
        phase = .idle
        smartMode = false
        hotkeyTriggered = false
        streamingActive = false
        streamingConfirmed = ""
        streamingVolatile = ""
    }

    func setModel(_ status: ModelStatus) {
        modelStatus = status
    }

    func markLaunchResolved() {
        launchResolved = true
    }
}
