import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Combine

/// App-level singleton. Owns recorder, transcriber, state, and hotkey registration.
/// Lives for the full app lifetime — independent of any window.
final class AppController: ObservableObject {
    static let shared = AppController()

    // Lazy: defer audio-unit initialization until after mic permission has been resolved.
    // Eager construction at singleton init touches CoreAudio before TCC has been queried, which can re-prompt on rebuild.
    private(set) lazy var recorder: Recorder = Recorder()
    let transcriber = Transcriber()
    let manager:      ModelManager

    @Published var state          = RecordingState()
    @Published var installedTiers: [UInt8] = []

    private let settings = SettingsStore.shared
    private var transcribeTask:    Task<Void, Never>?
    private var permissionPoller:  Timer?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var appNapToken: NSObjectProtocol?

    private init() {
        guard let m = try? ModelManager(modelsDir: Self.modelsDirectory()) else {
            preconditionFailure("ModelManager init failed — TapTalk cannot run without a writable models directory")
        }
        manager = m
    }

    static func modelsDirectory() -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("talk.tap.app/models")
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback.path
        }
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Called once at app launch.
    func setup() {
        suppressAppNap()
        refresh()
        FloatingPillController.shared.hide()
        resolveMicThenSetupHotkey()
        observeBackendChanges()
    }

    // App Nap throttles unfocused apps; the throttling stalls the CGEvent tap callback,
    // and macOS then disables the tap by timeout — silently breaking the global hotkey.
    // Holding a userInitiated activity keeps the app at full responsiveness while still
    // allowing the system to idle-sleep when the user is away.
    private func suppressAppNap() {
        guard appNapToken == nil else { return }
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Global push-to-talk hotkey delivery"
        )
    }

    // dropFirst skips @Published replay on subscribe — avoids stop() at launch when nothing is running
    private func observeBackendChanges() {
        settings.$llmBackend
            .combineLatest(settings.$llmEnabled)
            .dropFirst()
            .sink { backend, enabled in
                if !(backend == .local && enabled) {
                    LlamaServerManager.shared.stop()
                }
            }
            .store(in: &settingsCancellables)
    }

    // Ensures mic permission is resolved before the hotkey goes live.
    // CPAL blocks the main thread during the CoreAudio permission dialog; if the hotkey
    // fires while that block is in progress, keyUp is missed and recording gets stuck.
    private func resolveMicThenSetupHotkey() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized, .denied, .restricted:
            setupHotkey()
        case .notDetermined:
            // Show dialog and wait for the user to respond before registering the hotkey.
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.setupHotkey() }
            }
        @unknown default:
            setupHotkey()
        }
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

        Task.detached { [weak self] in
            guard let self = self else { return }
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
            state.smartMode       = false
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
        state.recording       = false
        state.cancelled       = false
        state.hotkeyTriggered = false
        state.smartMode       = false
        state.rewriting       = false
        _ = try? recorder.stop()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        state.transcribing = false
        state.rewriting    = false
        state.smartMode    = false
        state.cancelled    = true
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    func stopAndTranscribe() {
        guard state.recording else { return }
        state.recording    = false
        state.transcribing = true
        state.cancelled    = false
        state.status       = "Transcribing..."
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.show(state: .transcribing)

        let lang          = settings.selectedLanguage
        let engine        = settings.transcriptionEngine
        let cloudModel    = settings.cloudModel
        let apiKey        = settings.apiKey
        let smartMode     = state.smartMode
        let segments      = settings.dictionarySegments
        let llmEnabled    = settings.llmEnabled
        let llmBackend    = settings.llmBackend
        let llmClient     = makeLLMClient(settings: settings)
        let llmMissingForSmart = smartMode && llmEnabled && llmClient == nil && llmBackend == .local

        transcribeTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let audio = try self.recorder.stop()

                if Task.isCancelled {
                    await MainActor.run {
                        self.state.transcribing = false
                        self.state.smartMode    = false
                        self.state.status = "Cancelled"
                        FloatingPillController.shared.hide()
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

                if Task.isCancelled { return }

                // Post-processing pipeline
                var processed = PostProcessingService.applyDictionary(result.text, segments: segments)

                if smartMode && llmEnabled, let client = llmClient, !processed.isEmpty {
                    await MainActor.run {
                        self.state.transcribing = false
                        self.state.rewriting    = true
                        FloatingPillController.shared.show(state: .rewriting)
                    }
                    let appName = await MainActor.run { AppContextService.frontmostAppName() }
                    let prompt = AppContextService.systemPrompt(appName: appName)
                    processed = (try? await PostProcessingService.rewrite(processed, systemPrompt: prompt, client: client)) ?? processed
                }

                await MainActor.run {
                    guard !self.state.cancelled else { return }
                    self.state.transcribing = false
                    self.state.rewriting    = false
                    self.state.smartMode    = false

                    if result.text.isEmpty {
                        self.state.status = "Too short — hold longer"
                        FloatingPillController.shared.hide()
                    } else {
                        self.state.transcriptText = processed
                        self.state.transcriptLang = result.language
                        self.state.transcriptMs   = result.durationMs
                        self.state.audioDuration  = audio.durationSecs
                        self.state.status         = llmMissingForSmart
                            ? "Local model not installed — pasted transcript only"
                            : "Done"
                        if self.state.hotkeyTriggered {
                            PasteService.paste(processed)
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
                    self.state.rewriting    = false
                    self.state.smartMode    = false
                    self.state.status = "Error: \(error.localizedDescription)"
                    FloatingPillController.shared.hide()
                }
            }
        }
    }

    /// Registers (or re-registers) the global hotkey with the current key code.
    /// Safe to call multiple times — unregisters first. No-op if recording is active.
    func setupHotkey() {
        guard !state.recording, !state.transcribing else { return }
        guard AccessibilityService.hasPermission else {
            AccessibilityService.requestPermission()
            startPermissionPoller()
            return
        }

        HotkeyService.shared.unregister()
        HotkeyService.shared.unregisterSmart()
        HotkeyService.shared.setKeyCode(settings.hotkeyCode)
        HotkeyService.shared.register(
            keyDown: { [weak self] in
                guard let self else { return }
                if state.transcribing { cancelTranscription() }
                state.hotkeyTriggered = true
                state.smartMode       = false
                startRecording()
            },
            keyUp: { [weak self] in
                guard let self else { return }
                if state.recording { stopAndTranscribe() }
            }
        )

        if settings.smartHotkeyEnabled {
            HotkeyService.shared.setSmartKeyCode(settings.smartHotkeyCode)
            HotkeyService.shared.registerSmart(
                keyDown: { [weak self] in
                    guard let self else { return }
                    if state.transcribing { cancelTranscription() }
                    state.hotkeyTriggered = true
                    state.smartMode       = true
                    startRecording()
                },
                keyUp: { [weak self] in
                    guard let self else { return }
                    if state.recording { stopAndTranscribe() }
                }
            )
        }

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
