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
    @Published var status = ""

    @Published private(set) var hotkeyTriggered = false
    @Published private(set) var smartMode = false

    @Published var transcriptText = ""
    @Published var transcriptLang = ""
    @Published var transcriptMs: UInt64 = 0
    @Published var audioDuration: Float = 0

    var recording: Bool { phase == .recording }
    var transcribing: Bool { phase == .transcribing }
    var rewriting: Bool { phase == .rewriting }
    var modelReady: Bool { modelStatus == .ready }
    var loadingModel: Bool { modelStatus == .loading }
    var canRecord: Bool { modelStatus == .ready && phase == .idle }

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
    }

    func cancel() {
        phase = .idle
        smartMode = false
        hotkeyTriggered = false
    }

    func setModel(_ status: ModelStatus) {
        modelStatus = status
    }
}
