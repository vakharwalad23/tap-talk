import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Combine

/// App-level singleton. Owns recorder, engines, state, and hotkey registration.
/// Lives for the full app lifetime — independent of any window.
final class AppController: ObservableObject {
    static let shared = AppController()

    // Lazy: defer audio-unit initialization until after mic permission has been resolved.
    // Eager construction at singleton init touches CoreAudio before TCC has been queried, which can re-prompt on rebuild.
    private(set) lazy var recorder: Recorder = Recorder()
    let parakeet    = ParakeetEngine()
    let manager:      ModelManager

    @Published var state = RecordingState()

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

    // Live-typing state. Non-nil only while a streaming recording session is in flight.
    let liveInserter = LiveInserter()
    private var streamingEngine: EouStreamingEngine?
    private var streamingChunkHandler: StreamingChunkHandler?
    private var streamConsumerTask: Task<Void, Never>?

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
        reconcileStreamingFlag()
        warmUpStreamingEngineIfNeeded()
        refresh()
        FloatingPillController.shared.hide()
        resolveMicThenSetupHotkey()
        observeBackendChanges()
        observeSystemEvents()
    }

    // Forces streamingEnabled=false when the EOU model isn't installed so the Settings
    // toggle (hidden when EOU is missing) can't disagree with the persisted bool.
    private func reconcileStreamingFlag() {
        if settings.streamingEnabled && !EouStreamingEngine.isInstalled() {
            settings.streamingEnabled = false
        }
    }

    // Warms Core ML JIT caches for the EOU model so the first streaming session starts in
    // hundreds of ms instead of seconds — cuts the cold-start audio backlog window.
    private func warmUpStreamingEngineIfNeeded() {
        guard settings.streamingEnabled, EouStreamingEngine.isInstalled() else { return }
        Task.detached { await EouStreamingEngine.warmUp() }
    }

    // Reclaims disk from downloads interrupted by a previous app quit (the Rust core sweeps
    // its own dir at init). Best-effort, off the main thread.
    private func sweepDownloadResidue() {
        Task.detached {
            ParakeetEngine.sweepOrphans()
            EouStreamingEngine.sweepOrphans()
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
        loadActiveEngine()
    }

    private enum ActiveEngine { case parakeet, none }

    private enum EnginePlan {
        case cloud
        case parakeet
        case unavailable(status: String)
    }

    func loadActiveEngine() {
        engineLoadGeneration &+= 1
        let gen = engineLoadGeneration
        let plan = resolveEnginePlan()

        // Immediate UI feedback before the (serialized) load runs.
        switch plan {
        case .cloud:              state.setModel(.ready);   state.status = "Cloud (OpenAI)"
        case .parakeet:           state.setModel(.loading); state.status = "Loading Parakeet..."
        case .unavailable(let s): state.setModel(.none);    state.status = s
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
        case .parakeet:
            return ParakeetEngine.isInstalled()
                ? .parakeet
                : .unavailable(status: "Parakeet not installed — download it in Models")
        }
    }

    private func applyEnginePlan(_ plan: EnginePlan, generation gen: Int) async {
        switch plan {
        case .parakeet:            await releaseEngines(keep: .parakeet)
        case .cloud, .unavailable: await releaseEngines(keep: .none)
        }
        guard await isCurrentGeneration(gen) else { return }

        switch plan {
        case .cloud, .unavailable:
            return  // nothing to load; UI already set
        case .parakeet:
            do {
                try await parakeet.ensureLoaded()
                await finishLoad(gen, model: .ready, status: "Parakeet ready")
            } catch {
                await finishLoad(gen, model: .none, status: "Parakeet failed: \(error.localizedDescription)")
            }
        }
    }

    // Unloads every engine except the one being kept, freeing its RAM/ANE footprint.
    private func releaseEngines(keep: ActiveEngine) async {
        if keep != .parakeet { await parakeet.unload() }
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
        guard streamingEngine == nil else { return }
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

            if shouldStream(smart: smart) {
                beginStreamingSession()
            }
        } catch {
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    // Whether the current recording should stream live text. Smart Mode opts out — the LLM
    // rewrite needs the full transcript — and the cloud engine does not support streaming.
    // Also requires the EOU 120M realtime model to be installed; without the EOU realtime
    // model, fall back to whole-clip transcription.
    private func shouldStream(smart: Bool) -> Bool {
        settings.streamingEnabled
            && settings.transcriptionEngine == .local
            && settings.localEngine.supportsStreaming
            && !smart
            && EouStreamingEngine.isInstalled()
    }

    // Boots the streaming engine and wires the recorder's chunk callback to feed it.
    // Chunk callback is set IMMEDIATELY (before engine.start finishes loading), so audio
    // buffers in the engine's FIFO from the first sample — no audio is dropped while the
    // model loads on a cold start. Updates land on the main actor and drive both the
    // LiveInserter (live typing) and the UI preview.
    private func beginStreamingSession() {
        let rate = Double(recorder.inputSampleRate() ?? 16_000)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else {
            state.status = "Live typing failed: invalid sample rate"
            return
        }
        let engine = EouStreamingEngine()
        streamingEngine = engine
        liveInserter.begin()
        state.streamingActive = true
        state.streamingConfirmed = ""
        state.streamingVolatile = ""

        // Don't keep a previously loaded batch model resident
        // while EOU streams. Serialize through engineTask so a concurrent loadActiveEngine
        // can't reload an engine mid-stream; bumping the generation makes any in-flight load
        // a no-op when it resumes.
        engineLoadGeneration &+= 1
        let previousEngineTask = engineTask
        engineTask = Task { [weak self] in
            await previousEngineTask?.value
            await self?.releaseEngines(keep: .none)
        }

        // Wire chunks to the engine's Sendable FIFO right away. Yielding into AsyncStream
        // is sync and order-preserving — no Task scheduling race per audio chunk.
        let handler = StreamingChunkHandler(format: format, continuation: engine.inputContinuation)
        streamingChunkHandler = handler
        recorder.setAudioChunkCallback(callback: handler)

        streamConsumerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start(sampleRate: rate)
                let stream = await engine.updates
                for await update in stream {
                    if update.isFinal { continue }   // commit() handles the final pass
                    await MainActor.run {
                        guard self.streamingEngine === engine else { return }
                        self.liveInserter.update(confirmed: update.confirmed, volatile: update.volatile)
                        self.state.streamingConfirmed = update.confirmed
                        self.state.streamingVolatile = update.volatile
                    }
                }
            } catch {
                // Cancel the engine to free a half-loaded model before tearing down session state.
                await engine.cancel()
                await MainActor.run {
                    self.state.status = "Live typing failed: \(error.localizedDescription)"
                    self.liveInserter.cancel()
                    self.tearDownStreamingSession()
                }
            }
        }
    }

    private func tearDownStreamingSession() {
        // Idempotent: a double-call (cancel arriving while error path also tears down)
        // becomes a no-op once the session flags are already cleared.
        guard state.streamingActive || streamingEngine != nil || streamConsumerTask != nil else { return }
        recorder.clearAudioChunkCallback()
        streamConsumerTask?.cancel()
        streamConsumerTask = nil
        streamingChunkHandler = nil
        streamingEngine = nil
        state.streamingActive = false
        state.streamingConfirmed = ""
        state.streamingVolatile = ""
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
        // Reset UI/state first; tear the audio stream down off the main thread. A slow
        // cpal pause() (CoreAudio start->pause race) used to block this method and leave
        // the app stuck in the .recording phase.
        state.cancel()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
        scheduleIdleRelease()

        // Streaming session: backspace whatever was typed live, then tear down.
        // Capture the engine locally then clear `streamingEngine` immediately (via teardown) so
        // a concurrent error path can't re-touch the same instance during the detached cancel.
        let activeStreamingEngine = streamingEngine
        if activeStreamingEngine != nil {
            liveInserter.cancel()
            tearDownStreamingSession()
        }
        Task.detached { [recorder, activeStreamingEngine] in
            _ = try? recorder.stop()
            if let engine = activeStreamingEngine { await engine.cancel() }
        }
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

        // Streaming session: text was typed live; just finalize, reconcile, and clean up.
        if let engine = streamingEngine {
            // Clear instance var immediately so a concurrent cancelRecording can't re-touch
            // this engine while the detached finish() is in flight.
            self.streamingEngine = nil
            recorder.clearAudioChunkCallback()
            let segments = settings.dictionarySegments
            let hotkeyTriggeredLocal = hotkeyTriggered
            transcribeTask = Task.detached { [weak self] in
                guard let self else { return }
                _ = try? self.recorder.stop()
                do {
                    let final = try await engine.finish()
                    let processed = PostProcessingService.applyDictionary(final, segments: segments)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let typed = self.liveInserter.commit(processed)
                        // Tear down streaming flags first so the final-transcript card shows
                        // without a one-frame overlap with the streaming preview.
                        self.tearDownStreamingSession()
                        if processed.isEmpty {
                            self.state.finish()
                            self.state.status = "Too short — hold longer"
                            FloatingPillController.shared.hide()
                        } else {
                            self.state.transcriptText = processed
                            self.state.transcriptLang = "auto"
                            self.state.transcriptMs = 0
                            self.state.audioDuration = 0
                            self.state.finish()
                            self.state.status = "Done"
                            // Fallback: live typing was dropped (secure input / focus moved) —
                            // paste the final utterance so it isn't silently lost. Fires
                            // regardless of how recording was triggered.
                            if !typed {
                                PasteService.paste(processed)
                            }
                            if hotkeyTriggeredLocal {
                                FloatingPillController.shared.show(state: .done)
                            } else {
                                FloatingPillController.shared.hide()
                            }
                        }
                        self.scheduleIdleRelease()
                    }
                } catch {
                    // Free the half-loaded engine before resetting session state.
                    await engine.cancel()
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.state.finish()
                        self.state.status = "Live typing error: \(error.localizedDescription)"
                        FloatingPillController.shared.hide()
                        self.tearDownStreamingSession()
                        self.scheduleIdleRelease()
                    }
                }
            }
            return
        }

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
                    let out = try await self.parakeet.transcribe(samples: audio.samples)
                    // Parakeet auto-detects (EU); don't fabricate a specific language label.
                    result = TranscriptionResult(text: out.text, language: "auto", durationMs: out.processingMs)
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

// Forwards live mono audio chunks from the Rust recorder to the streaming engine via a
// Sendable FIFO continuation. Yielding is sync and thread-safe, preserving arrival order —
// critical for streaming ASR (out-of-order chunks corrupt the recognizer state).
final class StreamingChunkHandler: AudioChunkCallback {
    let format: AVAudioFormat
    let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    init(format: AVAudioFormat, continuation: AsyncStream<AVAudioPCMBuffer>.Continuation) {
        self.format = format
        self.continuation = continuation
    }
    func onChunk(samples: [Float]) {
        guard !samples.isEmpty, let buffer = makeBuffer(samples: samples, format: format) else { return }
        continuation.yield(buffer)
    }
}
