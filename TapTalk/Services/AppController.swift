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
    private var wakeObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var hasRequestedAccessibilityPermission = false

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
        observeSystemEvents()
    }

    private func observeSystemEvents() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.setupHotkey()
        }

        // didBecomeActiveNotification does not fire reliably for MenuBarExtra-only apps.
        // didActivateApplicationNotification fires whenever the user interacts with any
        // part of TapTalk (menu bar, window, or dock icon).
        didBecomeActiveObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            self.setupHotkey()
        }
    }

    // App Nap throttles unfocused apps; the throttling stalls the CGEvent tap callback,
    // and macOS then disables the tap by timeout — silently breaking the global hotkey.
    private func suppressAppNap() {
        guard appNapToken == nil else { return }
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
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
        case .authorized:
            warmUpAudioStream()
            setupHotkey()
        case .denied, .restricted:
            setupHotkey()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.warmUpAudioStream() }
                    self?.setupHotkey()
                }
            }
        @unknown default:
            setupHotkey()
        }
    }

    // Pre-creates the CoreAudio AudioUnit so TCC validation happens at
    // launch — not inside the hotkey callback where it blocks the main thread.
    // Touches `recorder` on main thread first (safe lazy init) then warms
    // up the CPAL stream in background.
    private func warmUpAudioStream() {
        let rec = recorder
        Task.detached {
            try? rec.warmUp()
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
            state.setModel(.none)
        }
    }

    func loadSelectedTier() {
        guard settings.transcriptionEngine == .local else {
            state.setModel(.ready)
            state.status = "Cloud (OpenAI)"
            return
        }

        let tier = settings.selectedTier
        guard installedTiers.contains(tier) else { return }
        state.setModel(.loading)
        let tierName = availableTiers().first(where: { $0.id == tier })?.name ?? ""
        state.status = "Loading \(tierName)..."

        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try self.transcriber.loadModel(tier: tier, modelsDir: Self.modelsDirectory())
                await MainActor.run {
                    self.state.setModel(.ready)
                    self.state.status = "\(tierName) ready"
                }
            } catch {
                await MainActor.run {
                    self.state.setModel(.none)
                    self.state.status = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleRecording() {
        if state.recording {
            stopAndTranscribe()
        } else {
            startRecording(hotkey: false, smart: false)
        }
    }

    func startRecording(hotkey: Bool, smart: Bool) {
        guard state.canRecord else { return }
        if state.transcribing { cancelTranscription() }
        do {
            try recorder.start()
            state.beginRecording(hotkey: hotkey, smart: smart)
            state.status = "Recording..."
            AppRecordingState.shared.isRecording = true
            FloatingPillController.shared.show(state: .recording)
        } catch {
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    func cancelRecording() {
        guard state.recording else { return }
        _ = try? recorder.stop()
        state.cancel()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        state.cancel()
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    func stopAndTranscribe() {
        guard state.recording else { return }

        let smartMode       = state.smartMode
        let hotkeyTriggered = state.hotkeyTriggered

        state.beginTranscribing()
        state.status = "Transcribing..."
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.show(state: .transcribing)

        let lang       = settings.selectedLanguage
        let engine     = settings.transcriptionEngine
        let cloudModel = settings.cloudModel
        let apiKey     = settings.apiKey
        let segments   = settings.dictionarySegments
        let llmEnabled = settings.llmEnabled
        let llmBackend = settings.llmBackend
        let llmClient  = makeLLMClient(settings: settings)
        let llmMissingForSmart = smartMode && llmEnabled && llmClient == nil && llmBackend == .local

        transcribeTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let audio = try self.recorder.stop()

                if Task.isCancelled {
                    await MainActor.run {
                        self.state.cancel()
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

                var processed = PostProcessingService.applyDictionary(result.text, segments: segments)

                var rewriteError: String?
                if smartMode && llmEnabled, let client = llmClient, !processed.isEmpty {
                    await MainActor.run {
                        self.state.beginRewriting()
                        FloatingPillController.shared.show(state: .rewriting)
                    }
                    let appName = await MainActor.run { AppContextService.frontmostAppName() }
                    let prompt = AppContextService.systemPrompt(appName: appName)
                    do {
                        processed = try await PostProcessingService.rewrite(processed, systemPrompt: prompt, client: client)
                    } catch {
                        rewriteError = error.localizedDescription
                    }
                }

                await MainActor.run {
                    guard !Task.isCancelled else { return }

                    if result.text.isEmpty {
                        self.state.finish()
                        self.state.status = "Too short — hold longer"
                        FloatingPillController.shared.hide()
                    } else {
                        self.state.transcriptText = processed
                        self.state.transcriptLang = result.language
                        self.state.transcriptMs   = result.durationMs
                        self.state.audioDuration  = audio.durationSecs
                        self.state.finish()
                        if let err = rewriteError {
                            self.state.status = "Smart rewrite failed: \(err)"
                        } else if llmMissingForSmart {
                            self.state.status = "Local model not installed — pasted transcript only"
                        } else {
                            self.state.status = "Done"
                        }
                        if hotkeyTriggered {
                            PasteService.paste(processed)
                            FloatingPillController.shared.show(state: .done)
                        } else {
                            FloatingPillController.shared.hide()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.state.finish()
                    self.state.status = "Error: \(error.localizedDescription)"
                    FloatingPillController.shared.hide()
                }
            }
        }
    }

    /// Registers (or re-registers) the global hotkey with the current key code.
    /// Safe to call multiple times — unregisters first.
    /// Only blocked during active recording (user holding key); transcribing/rewriting
    /// must not block because the tap may need re-creation after invalidation.
    func setupHotkey() {
        guard !state.recording else { return }
        guard AccessibilityService.hasPermission else {
            state.hotkeyActive = false
            if !hasRequestedAccessibilityPermission {
                hasRequestedAccessibilityPermission = true
                AccessibilityService.requestPermission()
                startPermissionPoller()
            }
            return
        }

        HotkeyService.shared.unregister()
        HotkeyService.shared.unregisterSmart()
        HotkeyService.shared.setKeyCode(settings.hotkeyCode)
        HotkeyService.shared.register(
            keyDown: { [weak self] in
                guard let self else { return }
                if state.transcribing { cancelTranscription() }
                startRecording(hotkey: true, smart: false)
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
                    startRecording(hotkey: true, smart: true)
                },
                keyUp: { [weak self] in
                    guard let self else { return }
                    if state.recording { stopAndTranscribe() }
                }
            )
        }

        state.hotkeyActive = HotkeyService.shared.isTapAlive
        permissionPoller?.invalidate()
        permissionPoller = nil
    }

    private func startPermissionPoller() {
        guard permissionPoller == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard AccessibilityService.hasPermission else { return }
            DispatchQueue.main.async {
                self?.hasRequestedAccessibilityPermission = false
                self?.setupHotkey()
                // tapCreate fails for unsigned apps until the process restarts after
                // the first-ever accessibility grant — prompt restart if tap is still dead
                if self?.state.hotkeyActive == false {
                    self?.promptRestartForAccessibility()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPoller = timer
    }

    private func promptRestartForAccessibility() {
        permissionPoller?.invalidate()
        permissionPoller = nil
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "TapTalk needs to restart to activate the global hotkey after accessibility permission is granted."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(fileURLWithPath: Bundle.main.bundlePath)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            NSApp.terminate(nil)
        }
    }
}
