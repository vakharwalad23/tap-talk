import SwiftUI

final class RecordingState: ObservableObject {
    @Published var recording = false
    @Published var transcribing = false
    @Published var cancelled = false
    @Published var hotkeyTriggered = false
    @Published var status = ""
    @Published var transcriptText = ""
    @Published var transcriptLang = ""
    @Published var transcriptMs: UInt64 = 0
    @Published var audioDuration: Float = 0
    @Published var modelReady = false
    @Published var loadingModel = false
    @Published var hotkeyActive = false
    @Published var rewriting = false
    @Published var smartMode = false

    var canRecord: Bool { modelReady && !recording && !loadingModel }
}
