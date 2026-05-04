import SwiftUI
import Carbon.HIToolbox
import AVFoundation

/// App-level singleton. Owns recorder, transcriber, state, and hotkey registration.
/// Lives for the full app lifetime — independent of any window.
final class AppController: ObservableObject {
    static let shared = AppController()

    let recorder    = Recorder()
    let transcriber = Transcriber()
    let manager:      ModelManager

    @Published var state          = RecordingState()
    @Published var installedTiers: [UInt8] = []

    private let settings = SettingsStore.shared
    private var transcribeTask:    Task<Void, Never>?
    private var permissionPoller:  Timer?

    private init() {
        manager = ModelManager(modelsDir: Self.modelsDirectory())
    }

    static func modelsDirectory() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Called once at app launch.
    func setup() {
        // Request mic permission now (window is open) so it never blocks mid-recording.
        // CPAL blocks the main thread during the permission dialog; if that happens during
        // a hotkey keyDown callback the matching keyUp is missed and recording gets stuck.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        refresh()
        setupHotkey()
        FloatingPillController.shared.hide()  // show idle pill
    }

    func refresh() {
        installedTiers = manager.installedTiers().sorted()
        if let first = installedTiers.first {
            if !installedTiers.contains(settings.selectedTier) {
                settings.selectedTier = first
            }
            loadSelectedTier()
        } else {
            state.status = "No models installed"
            state.modelReady = false
        }
    }

    func loadSelectedTier() {
        guard settings.transcriptionEngine == .local else {
            state.modelReady = true
            state.status = "Cloud (OpenAI)"
            return
        }

        let tier = settings.selectedTier
        guard installedTiers.contains(tier) else { return }
        state.loadingModel = true
        state.modelReady = false
        let tierName = availableTiers().first(where: { $0.id == tier })?.name ?? ""
        state.status = "Loading \(tierName)..."

        Task.detached {
            do {
                try self.transcriber.loadModel(tier: tier, modelsDir: Self.modelsDirectory())
                await MainActor.run {
                    self.state.loadingModel = false
                    self.state.modelReady   = true
                    self.state.status       = "\(tierName) ready"
                }
            } catch {
                await MainActor.run {
                    self.state.loadingModel = false
                    self.state.status       = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleRecording() {
        if state.recording {
            stopAndTranscribe()
        } else {
            state.hotkeyTriggered = false
            startRecording()
        }
    }

    func startRecording() {
        guard state.canRecord else { return }
        if state.transcribing { cancelTranscription() }
        do {
            try recorder.start()
            state.recording = true
            state.status = "Recording..."
            AppRecordingState.shared.isRecording = true
            FloatingPillController.shared.show(state: .recording)
        } catch {
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    func cancelRecording() {
        guard state.recording else { return }
        state.recording = false
        _ = try? recorder.stop()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        state.transcribing = false
        state.cancelled    = true
    }

    func stopAndTranscribe() {
        guard state.recording else { return }
        state.recording    = false
        state.transcribing = true
        state.cancelled    = false
        state.status       = "Transcribing..."
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.show(state: .transcribing)

        let lang       = settings.selectedLanguage
        let engine     = settings.transcriptionEngine
        let cloudModel = settings.cloudModel
        let apiKey     = settings.apiKey

        transcribeTask = Task.detached {
            do {
                let audio = try self.recorder.stop()

                if Task.isCancelled {
                    await MainActor.run {
                        self.state.transcribing = false
                        self.state.status = "Cancelled"
                    }
                    return
                }

                let result: TranscriptionResult
                if engine == .cloud {
                    result = try transcribeCloud(
                        samples: audio.samples,
                        language: lang,
                        model: cloudModel,
                        apiKey: apiKey
                    )
                } else {
                    result = try self.transcriber.transcribe(
                        samples: audio.samples,
                        language: lang
                    )
                }

                await MainActor.run {
                    guard !self.state.cancelled else { return }
                    self.state.transcribing = false
                    if result.text.isEmpty {
                        self.state.status = "Too short — hold longer"
                        FloatingPillController.shared.hide()
                    } else {
                        self.state.transcriptText = result.text
                        self.state.transcriptLang = result.language
                        self.state.transcriptMs   = result.durationMs
                        self.state.audioDuration  = audio.durationSecs
                        self.state.status         = "Done"
                        if self.state.hotkeyTriggered {
                            PasteService.paste(result.text)
                            FloatingPillController.shared.show(state: .done)
                        } else {
                            FloatingPillController.shared.hide()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard !self.state.cancelled else { return }
                    self.state.transcribing = false
                    self.state.status = "Error: \(error.localizedDescription)"
                    FloatingPillController.shared.hide()
                }
            }
        }
    }

    /// Registers (or re-registers) the global hotkey with the current key code.
    /// Safe to call multiple times — unregisters first.
    func setupHotkey() {
        guard AccessibilityService.hasPermission else {
            AccessibilityService.requestPermission()
            startPermissionPoller()
            return
        }

        HotkeyService.shared.unregister()
        HotkeyService.shared.setKeyCode(settings.hotkeyCode)
        HotkeyService.shared.register(
            keyDown: { [weak self] in
                guard let self else { return }
                if state.transcribing { cancelTranscription() }
                state.hotkeyTriggered = true
                startRecording()
            },
            keyUp: { [weak self] in
                guard let self else { return }
                if state.recording { stopAndTranscribe() }
            }
        )
        state.hotkeyActive = true
        permissionPoller?.invalidate()
        permissionPoller = nil
    }

    private func startPermissionPoller() {
        guard permissionPoller == nil else { return }
        permissionPoller = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard AccessibilityService.hasPermission else { return }
            DispatchQueue.main.async { self?.setupHotkey() }
        }
    }
}
