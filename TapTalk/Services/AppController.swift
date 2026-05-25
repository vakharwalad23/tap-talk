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
    let parakeet    = ParakeetEngine()
    let whisperKit  = WhisperKitEngine()
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
    private var recordingWatchdog: DispatchWorkItem?
    // Stable owner for the Rust level callback — its lifetime must outlast the audio thread.
    private let levelHandler = PillLevelHandler()

    // Bumped on every engine (re)load so a superseded async load/unload can no-op instead
    // of racing the newer one. All engine load/unload runs serialized through engineTask.
    private var engineLoadGeneration = 0
    private var engineTask: Task<Void, Never>?
    // Releases the loaded model after a period of inactivity so an idle app holds no model.
    private var idleReleaseTimer: Timer?
    private let idleReleaseSeconds: TimeInterval = 300

    // AppleSpeechEngine is macOS 26+, so it can't be a plain stored property. Cache one
    // instance behind a main-isolated, availability-gated accessor (avoids per-call setup
    // and keeps appleEngineStorage access single-threaded).
    private var appleEngineStorage: Any?
    @available(macOS 26, *)
    @MainActor
    private var apple: AppleSpeechEngine {
        if let engine = appleEngineStorage as? AppleSpeechEngine { return engine }
        let engine = AppleSpeechEngine()
        appleEngineStorage = engine
        return engine
    }

    private let maxRecordingSeconds: TimeInterval = 120

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
        sweepDownloadResidue()
        refresh()
        FloatingPillController.shared.hide()
        resolveMicThenSetupHotkey()
        observeBackendChanges()
        observeSystemEvents()
    }

    // Reclaims disk from downloads interrupted by a previous app quit (the Rust core sweeps
    // its own dir at init). Best-effort, off the main thread.
    private func sweepDownloadResidue() {
        Task.detached {
            WhisperKitEngine.sweepOrphans()
            ParakeetEngine.sweepOrphans()
        }
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

        // Reload the active engine when the user switches transcription engine or local model.
        settings.$localEngine
            .combineLatest(settings.$transcriptionEngine)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.clearTranscript()   // the old result belongs to the old engine
                self?.refresh()
            }
            .store(in: &settingsCancellables)

        // Reload when the active WhisperKit model changes.
        settings.$whisperKitModel
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.settings.localEngine == .whisperKit else { return }
                self.clearTranscript()
                self.loadSelectedTier()
            }
            .store(in: &settingsCancellables)
    }

    private func clearTranscript() {
        state.transcriptText = ""
        state.transcriptLang = ""
        state.transcriptMs = 0
        state.audioDuration = 0
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
        rec.setLevelCallback(callback: levelHandler)
        Task.detached {
            try? rec.warmUp()
        }
    }

    func refresh() {
        installedTiers = manager.installedTiers().sorted()

        // Only the Rust whisper.cpp engine depends on installed whisper tiers; cloud and the
        // other local engines (Parakeet, WhisperKit, Apple) manage their own models.
        if settings.transcriptionEngine == .cloud || settings.localEngine != .whisper {
            loadSelectedTier()
            return
        }

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

    private enum ActiveEngine { case whisper, parakeet, whisperKit, apple, none }

    private enum EnginePlan {
        case cloud
        case whisper(tier: UInt8, name: String)
        case parakeet
        case whisperKit(WhisperKitEngine.Model)
        case apple
        case unavailable(status: String)
    }

    func loadSelectedTier() {
        engineLoadGeneration &+= 1
        let gen = engineLoadGeneration
        let plan = resolveEnginePlan()

        // Immediate UI feedback before the (serialized) load runs.
        switch plan {
        case .cloud:                state.setModel(.ready);   state.status = "Cloud (OpenAI)"
        case .apple:                state.setModel(.ready);   state.status = "Apple Speech ready"
        case .whisper(_, let name): state.setModel(.loading); state.status = "Loading \(name)..."
        case .parakeet:             state.setModel(.loading); state.status = "Loading Parakeet..."
        case .whisperKit(let m):    state.setModel(.loading); state.status = "Loading WhisperKit \(m.displayName)..."
        case .unavailable(let s):   state.setModel(.none);    state.status = s
        }

        // Serialize all engine load/unload through one chain so a rapid switch can't run an
        // unload after the next load; stale plans no-op via the generation check.
        let previous = engineTask
        engineTask = Task { [weak self] in
            await previous?.value
            guard let self, await self.isCurrentGeneration(gen) else { return }
            await self.applyEnginePlan(plan, generation: gen)
        }
    }

    private func resolveEnginePlan() -> EnginePlan {
        guard settings.transcriptionEngine == .local else { return .cloud }
        switch settings.localEngine {
        case .whisper:
            let tier = settings.selectedTier
            guard installedTiers.contains(tier) else {
                return .unavailable(status: installedTiers.isEmpty ? "No models installed" : "Select an installed model")
            }
            let name = availableTiers().first(where: { $0.id == tier })?.name ?? ""
            return .whisper(tier: tier, name: name)
        case .parakeet:
            return ParakeetEngine.isInstalled()
                ? .parakeet
                : .unavailable(status: "Parakeet not installed — download it in Models")
        case .whisperKit:
            let m = settings.whisperKitModel
            return WhisperKitEngine.isInstalled(m)
                ? .whisperKit(m)
                : .unavailable(status: "WhisperKit \(m.displayName) not installed — download it in Models")
        case .appleSpeech:
            if #available(macOS 26, *) { return .apple }
            return .unavailable(status: "Apple Speech requires macOS 26")
        }
    }

    private func applyEnginePlan(_ plan: EnginePlan, generation gen: Int) async {
        switch plan {
        case .whisper:             await releaseEngines(keep: .whisper)
        case .parakeet:            await releaseEngines(keep: .parakeet)
        case .whisperKit:          await releaseEngines(keep: .whisperKit)
        case .apple:               await releaseEngines(keep: .apple)
        case .cloud, .unavailable: await releaseEngines(keep: .none)
        }
        guard await isCurrentGeneration(gen) else { return }

        switch plan {
        case .cloud, .apple, .unavailable:
            return  // nothing to load; UI already set
        case .whisper(let tier, let name):
            do {
                try transcriber.loadModel(tier: tier, modelsDir: Self.modelsDirectory())
                await finishLoad(gen, model: .ready, status: "\(name) ready")
            } catch {
                await finishLoad(gen, model: .none, status: "Failed: \(error.localizedDescription)")
            }
        case .parakeet:
            do {
                try await parakeet.ensureLoaded()
                await finishLoad(gen, model: .ready, status: "Parakeet ready")
            } catch {
                await finishLoad(gen, model: .none, status: "Parakeet failed: \(error.localizedDescription)")
            }
        case .whisperKit(let m):
            do {
                try await whisperKit.ensureLoaded(m)
                await finishLoad(gen, model: .ready, status: "WhisperKit \(m.displayName) ready")
            } catch {
                await finishLoad(gen, model: .none, status: "WhisperKit failed: \(error.localizedDescription)")
            }
        }
    }

    // Unloads every engine except the one being kept, freeing its RAM/ANE footprint.
    private func releaseEngines(keep: ActiveEngine) async {
        if keep != .whisper { transcriber.unload() }
        if keep != .parakeet { await parakeet.unload() }
        if keep != .whisperKit { await whisperKit.unload() }
        if #available(macOS 26, *), keep != .apple {
            let apple = await MainActor.run { self.appleEngineStorage as? AppleSpeechEngine }
            if let apple { await apple.unload() }
        }
    }

    @MainActor private func isCurrentGeneration(_ gen: Int) -> Bool { engineLoadGeneration == gen }

    @MainActor private func finishLoad(_ gen: Int, model: RecordingState.ModelStatus, status: String) {
        guard engineLoadGeneration == gen else { return }
        state.setModel(model)
        state.status = status
        if model == .ready { scheduleIdleRelease() }
    }

    // MARK: Idle release

    private func scheduleIdleRelease() {
        idleReleaseTimer?.invalidate()
        idleReleaseTimer = Timer.scheduledTimer(withTimeInterval: idleReleaseSeconds, repeats: false) { [weak self] _ in
            self?.releaseIdleEngines()
        }
    }

    private func cancelIdleRelease() {
        idleReleaseTimer?.invalidate()
        idleReleaseTimer = nil
    }

    // Frees the resident model after inactivity. modelStatus stays .ready so recording still
    // works — the transcribe path reloads on demand (ensureLoaded / is_loaded).
    private func releaseIdleEngines() {
        guard state.phase == .idle else { return }
        engineLoadGeneration &+= 1
        let previous = engineTask
        engineTask = Task { [weak self] in
            await previous?.value
            await self?.releaseEngines(keep: .none)
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
        cancelIdleRelease()
        if state.transcribing { cancelTranscription() }
        do {
            try recorder.start()
            state.beginRecording(hotkey: hotkey, smart: smart)
            state.status = "Recording..."
            AppRecordingState.shared.isRecording = true
            FloatingPillController.shared.show(state: .recording)
            startRecordingWatchdog()
        } catch {
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    // Force-stops a recording that outlives the max duration — a final safety net
    // against a missed key-release leaving the app stuck in recording.
    private func startRecordingWatchdog() {
        recordingWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.recording else { return }
            self.stopAndTranscribe()
        }
        recordingWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingSeconds, execute: work)
    }

    private func cancelRecordingWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
    }

    func cancelRecording() {
        guard state.recording else { return }
        cancelRecordingWatchdog()
        _ = try? recorder.stop()
        state.cancel()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
        scheduleIdleRelease()
    }

    func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        state.cancel()
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
        scheduleIdleRelease()
    }

    func stopAndTranscribe() {
        guard state.recording else { return }
        cancelRecordingWatchdog()

        let smartMode       = state.smartMode
        let hotkeyTriggered = state.hotkeyTriggered

        state.beginTranscribing()
        state.status = "Transcribing..."
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.show(state: .transcribing)

        let lang       = settings.selectedLanguage
        let engine     = settings.transcriptionEngine
        let localEngine = settings.localEngine
        let wkModel    = settings.whisperKitModel
        let tier       = settings.selectedTier
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
                } else if localEngine == .parakeet {
                    let out = try await self.parakeet.transcribe(samples: audio.samples)
                    // Parakeet auto-detects (EU); don't fabricate a specific language label.
                    result = TranscriptionResult(text: out.text, language: "auto", durationMs: out.processingMs)
                } else if localEngine == .whisperKit {
                    let out = try await self.whisperKit.transcribe(samples: audio.samples, language: lang, model: wkModel)
                    result = TranscriptionResult(text: out.text, language: out.language, durationMs: out.processingMs)
                } else if localEngine == .appleSpeech {
                    if #available(macOS 26, *) {
                        let apple = await MainActor.run { self.apple }
                        let out = try await apple.transcribe(samples: audio.samples, language: lang)
                        result = TranscriptionResult(text: out.text, language: out.language, durationMs: out.processingMs)
                    } else {
                        throw CoreError.Transcription(msg: "Apple Speech requires macOS 26")
                    }
                } else {
                    // Reload on demand if an idle release unloaded the model.
                    if !self.transcriber.isLoaded() {
                        try self.transcriber.loadModel(tier: tier, modelsDir: Self.modelsDirectory())
                    }
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

                    // Guard on the final text (post dictionary/rewrite) so an empty result
                    // never gets pasted as a blank transcript.
                    if processed.isEmpty {
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
                    self.scheduleIdleRelease()
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.state.finish()
                    self.state.status = "Error: \(error.localizedDescription)"
                    FloatingPillController.shared.hide()
                    self.scheduleIdleRelease()
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

// Forwards live mic RMS from the Rust recorder to the floating pill on the main thread.
private final class PillLevelHandler: AudioLevelCallback {
    func onLevel(rms: Float) {
        DispatchQueue.main.async {
            FloatingPillController.shared.setLevel(rms)
        }
    }
}
