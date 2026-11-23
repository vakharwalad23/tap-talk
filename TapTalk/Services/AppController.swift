import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Combine
import TapTalkAudio
import TapTalkLearning
import TapTalkHotkeys
import os

/// App-level singleton. Owns recorder, engines, state, and hotkey registration.
/// Lives for the full app lifetime - independent of any window.
final class AppController: ObservableObject {
    static let shared = AppController()

    // Lazy: defer audio-unit initialization until after mic permission has been resolved.
    // Eager construction at singleton init touches CoreAudio before TCC has been queried, which can re-prompt on rebuild.
    private(set) lazy var recorder = DictationRecorder()
    let parakeet    = ParakeetEngine()
    let nemotron    = NemotronEngine()
    let orukeet     = OrukeetEngine()
    let manager:      ModelManager

    @Published var state = RecordingState()

    private let settings = SettingsStore.shared
    private var transcribeTask:    Task<Void, Never>?
    private var permissionPoller:  Timer?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var appNapToken: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var recordingWatchdog: DispatchWorkItem?
    // Core Audio start can block for seconds while a Bluetooth device changes mode, and a blocked
    // main thread makes macOS disable the hotkey tap, losing the key release. Starts run here in
    // press order; every stop waits behind them. recordingGeneration lets a late start failure
    // tell whether the recording it belonged to is still the current one.
    private let captureQueue = DispatchQueue(label: "talk.tap.capture", qos: .userInteractive)
    private var recordingGeneration = 0
    // A hotkey change made while recording (Smart Mode switched, a key rebound) waits here and is
    // applied the moment the recording ends, so it never touches the tap mid-press.
    private var hotkeySetupPending = false
    private var gesture = HotkeyGesture(mode: .hold)
    // Shown again after a shortcut cancel, which ends the recording without a status of its own.
    private var statusBeforeRecording = ""

    // Bumped on every engine (re)load so a superseded async load/unload can no-op instead
    // of racing the newer one. All engine load/unload runs serialized through engineTask.
    private var engineLoadGeneration = 0
    private var engineTask: Task<Void, Never>?
    // Releases the loaded model after a period of inactivity so an idle app holds no model.
    //
    // 30 minutes rather than 5. Reloading costs a measurable cold start - roughly double the
    // key-up->paste time on the next dictation - and holding the model is cheaper than it looks,
    // because Core ML weights are memory-mapped (164 MB resident with Parakeet loaded, against
    // ~490 MB on disk). A dictation tool is used in bursts across a day, so a 5 minute timer made
    // most dictations pay cold start.
    //
    // The timer is only a backstop; memoryPressureSource releases immediately when the system
    // actually wants the RAM, which is the signal that matters.
    private var idleReleaseTimer: Timer?
    private let idleReleaseSeconds: TimeInterval = 1800
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Live-typing state. Non-nil only while a streaming recording session is in flight.
    let liveInserter = LiveInserter()
    private var streamingEngine: EouStreamingEngine?
    private var streamConsumerTask: Task<Void, Never>?

    // Safety stops. A toggle recording has no held key to lose, so it may run longer.
    private let holdRecordingLimit: TimeInterval = 120
    private let toggleRecordingLimit: TimeInterval = 600

    private init() {
        guard let m = try? ModelManager(modelsDir: Self.modelsDirectory()) else {
            preconditionFailure("ModelManager init failed - TapTalk cannot run without a writable models directory")
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
        LlamaServerManager.stopOrphanedServer()
        sweepDownloadResidue()
        reconcileStreamingFlag()
        warmUpStreamingEngineIfNeeded()
        MainActor.assumeIsolated {
            OrukeetMigration.shared.evaluate()
            self.reconcileEngineSelection()
            UpdateService.shared.start()
        }
        refresh()
        FloatingPillController.shared.hide()
        setupAudioAndHotkey()
        observeBackendChanges()
        observeSystemEvents()
        observeMemoryPressure()
        state.markLaunchResolved()
        // Learned rules and the spell checker cost 8 to 46 ms on first use; paid after launch instead of
        // inside the first recording. Both are main-actor only.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = LearnedCorrections.shared
                if SettingsStore.shared.learnCorrections { CorrectionLearner.warmSpelling() }
            }
        }
    }

    // Holding a model resident is a bet that RAM is free. Let the system settle that bet rather
    // than a fixed timer: release everything the moment macOS reports pressure, so a long idle
    // hold never competes with what the user is actually doing.
    private func observeMemoryPressure() {
        guard memoryPressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.releaseIdleEngines()
            LlamaServerManager.shared.stop()
        }
        source.resume()
        memoryPressureSource = source
    }

    // Forces streamingEnabled=false when the EOU model isn't installed so the Settings
    // toggle (hidden when EOU is missing) can't disagree with the persisted bool.
    private func reconcileStreamingFlag() {
        if settings.streamingEnabled && !EouStreamingEngine.isInstalled() {
            settings.streamingEnabled = false
        }
    }

    // Warms Core ML JIT caches for the EOU model so the first streaming session starts in
    // hundreds of ms instead of seconds - cuts the cold-start audio backlog window.
    private func warmUpStreamingEngineIfNeeded() {
        guard settings.streamingEnabled, EouStreamingEngine.isInstalled() else { return }
        Task.detached { await EouStreamingEngine.warmUp() }
    }

    // Reclaims disk from downloads interrupted by a previous app quit (the Rust core sweeps
    // its own dir at init). Best-effort, off the main thread.
    private func sweepDownloadResidue() {
        Task.detached {
            ParakeetEngine.sweepOrphans()
            NemotronEngine.sweepOrphans()
            OrukeetEngine.sweepOrphans()
            EouStreamingEngine.sweepOrphans()
            AppContextService.warmUp()
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
            // Returning from System Settings is when a microphone grant or denial changes.
            MainActor.assumeIsolated { PermissionService.shared.refresh() }
            self.setupHotkey()
        }
    }

    // App Nap throttles unfocused apps; the throttling stalls the CGEvent tap callback,
    // and macOS then disables the tap by timeout - silently breaking the global hotkey.
    private func suppressAppNap() {
        guard appNapToken == nil else { return }
        appNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Global push-to-talk hotkey delivery"
        )
    }

    // dropFirst skips @Published replay on subscribe - avoids stop() at launch when nothing is running
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

        // Smart Mode on or off arms or disarms the Smart key at once. Delivered after the property
        // changes; @Published emits before its new value is stored, and setupHotkey reads it.
        settings.$llmEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setupHotkey() }
            .store(in: &settingsCancellables)

        // Reload the active engine when the user switches transcription engine or local model.
        settings.$localEngine
            .combineLatest(settings.$transcriptionEngine)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.clearTranscript()   // the old result belongs to the old engine
                self?.reconcileSelectedLanguage()
                self?.refresh()
            }
            .store(in: &settingsCancellables)

        // Launch only warms EOU when live typing was already on; turning it on later warms it now.
        settings.$streamingEnabled
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { _ in Task.detached { await EouStreamingEngine.warmUp() } }
            .store(in: &settingsCancellables)
    }

    // Starts the local LLM while the user is still speaking, so a cold server does not land on
    // the key-up path. Measured cold start roughly doubles a dictation, and this window is dead
    // time - recording has already begun and nothing else competes for it.
    //
    // Fire-and-forget and detached on purpose: this must never delay the recording it follows.
    // ensureRunning is a no-op when the server is already up and reachable.
    private func prewarmRewrite() {
        guard settings.llmEnabled,
              settings.llmBackend == .local,
              !settings.rewriteOptions.isEmpty,
              let modelPath = manager.llmModelPath(modelId: LocalIntelligenceInstaller.modelId)
        else { return }

        Task.detached(priority: .utility) {
            try? await LlamaServerManager.shared.ensureRunning(modelPath: modelPath)
        }
    }

    // Engines cover different language sets. A selection the new engine cannot produce
    // would leave the picker blank and silently fall back to auto-detect, so clear it.
    private func reconcileSelectedLanguage() {
        guard settings.transcriptionEngine == .local,
              let selected = settings.selectedLanguage else { return }
        let supported = settings.localEngine.supportedLanguages
        guard !supported.isEmpty else { return }
        if !supported.contains(where: { $0.id == selected }) {
            settings.selectedLanguage = nil
        }
    }

    private func clearTranscript() {
        state.transcriptText = ""
        state.transcriptLang = ""
        state.transcriptMs = 0
        state.audioDuration = 0
    }

    // Launch never prompts: the setup card asks for each permission when the user clicks it. A key
    // press without the microphone fails with a status line, never a dialog mid-press.
    private func setupAudioAndHotkey() {
        // Swept here, before any click can start a fetch whose partial folder this would delete.
        let store = vadStore
        store.sweepResidue()
        state.voiceDetector = store.isInstalled() ? .installed : .missing
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            warmUpAudioStream()
        }
        setupHotkey()
    }

    // Builds the audio graph off the main thread once permission is granted, so device setup never
    // lands inside the hotkey callback. Silero loads here only when installed: it is fetched after a
    // click that sets up speech, and until then recordings are transcribed untrimmed.
    func warmUpAudioStream() {
        let rec = recorder
        rec.setLevelHandler { rms in
            DispatchQueue.main.async { FloatingPillController.shared.setLevel(rms) }
        }
        let store = vadStore
        Task.detached {
            try? rec.warmUp()
            guard store.isInstalled() else { return }
            await Self.loadVoiceActivity(into: rec, from: store)
        }
    }

    /// Fetches Silero (~0.9 MB, pinned) after a click that sets up speech; a no-op once it is on disk.
    @MainActor func fetchVoiceDetectorIfMissing() {
        guard state.voiceDetector == .missing else { return }
        state.voiceDetector = .fetching
        let rec = recorder
        let store = vadStore
        Task.detached {
            do {
                try await store.install()
            } catch {
                Logger(subsystem: "talk.tap.app", category: "audio").error(
                    "voice activity download failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { AppController.shared.state.voiceDetector = .missing }
                return
            }
            await MainActor.run { AppController.shared.state.voiceDetector = .installed }
            await Self.loadVoiceActivity(into: rec, from: store)
        }
    }

    private var vadStore: VadModelStore {
        VadModelStore(modelsDirectory: URL(fileURLWithPath: Self.modelsDirectory(), isDirectory: true))
    }

    private static func loadVoiceActivity(into rec: DictationRecorder, from store: VadModelStore) async {
        do {
            try await rec.loadVoiceActivity(modelURL: store.modelURL)
        } catch {
            Logger(subsystem: "talk.tap.app", category: "audio").error(
                "voice activity unavailable, recordings stay untrimmed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the microphone hardware; called on app quit.
    func shutdownAudio() {
        recorder.shutdown()
    }

    func refresh() {
        loadActiveEngine()
    }

    // Engine preference order, used ONLY as the first-launch default and the fallback when
    // the active engine is removed. An explicit pick (a download or a Settings choice) is
    // remembered and wins over this order.
    static let enginePriority: [LocalEngine] = [.orukeet, .parakeet, .nemotron]

    nonisolated static func isInstalled(_ engine: LocalEngine) -> Bool {
        switch engine {
        case .parakeet: return ParakeetEngine.isInstalled()
        case .nemotron: return NemotronEngine.isInstalled()
        case .orukeet:  return OrukeetEngine.isInstalled()
        }
    }

    nonisolated static func highestPriorityInstalledEngine() -> LocalEngine? {
        enginePriority.first(where: { isInstalled($0) })
    }

    // Download selects the model: a just-downloaded engine becomes the active pick, so a
    // first-time user never needs a separate Settings trip.
    @MainActor func adoptDownloadedEngine(_ engine: LocalEngine) {
        settings.transcriptionEngine = .local
        settings.localEngine = engine
        refresh()
    }

    // At launch, keep the remembered engine if it is still installed; otherwise fall back by
    // priority (e.g. the selected engine was removed while the app was closed).
    @MainActor func reconcileEngineSelection() {
        guard settings.transcriptionEngine == .local, !Self.isInstalled(settings.localEngine),
              let best = Self.highestPriorityInstalledEngine() else { return }
        settings.localEngine = best
    }

    // After an engine is removed, if it was the active pick, fall back to the highest-priority
    // engine still installed, else the app default. Also refreshes the controller.
    @MainActor func handleEngineRemoved(_ removed: LocalEngine) {
        if settings.localEngine == removed {
            settings.localEngine = Self.highestPriorityInstalledEngine() ?? .orukeet
        }
        refresh()
    }

    private enum ActiveEngine { case parakeet, nemotron, orukeet, none }

    private enum EnginePlan {
        case cloud
        case parakeet
        case nemotron
        case orukeet
        case unavailable(status: String)
    }

    func loadActiveEngine() {
        engineLoadGeneration &+= 1
        let gen = engineLoadGeneration
        let plan = resolveEnginePlan()

        // Immediate UI feedback before the (serialized) load runs.
        switch plan {
        case .cloud:              state.setModel(.ready);   state.status = "Cloud (OpenAI)"
        case .parakeet:           state.setModel(.loading); state.status = "Loading \(LocalEngine.parakeet.displayName)..."
        case .nemotron:           state.setModel(.loading); state.status = "Loading \(LocalEngine.nemotron.displayName)..."
        case .orukeet:            state.setModel(.loading); state.status = "Loading \(LocalEngine.orukeet.displayName)..."
        case .unavailable(let s): state.setModel(.none);    state.status = s
        }

        // Serialize all engine load/unload through one chain so a rapid switch can't run an
        // unload after the next load; stale plans no-op via the generation check.
        // A dictation already transcribing loads and holds its own engine; switching after it lets
        // releaseEngines free that engine too, instead of leaving both resident until idle release.
        let previous = engineTask
        let inFlight = transcribeTask
        engineTask = Task { [weak self] in
            await previous?.value
            await inFlight?.value
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
                : .unavailable(status: "\(LocalEngine.parakeet.displayName) not installed - download it in Models")
        case .nemotron:
            return NemotronEngine.isInstalled()
                ? .nemotron
                : .unavailable(status: "\(LocalEngine.nemotron.displayName) not installed - download it in Models")
        case .orukeet:
            return OrukeetEngine.isInstalled()
                ? .orukeet
                : .unavailable(status: "\(LocalEngine.orukeet.displayName) not installed - download it in Models")
        }
    }

    private func applyEnginePlan(_ plan: EnginePlan, generation gen: Int) async {
        switch plan {
        case .parakeet:            await releaseEngines(keep: .parakeet)
        case .nemotron:            await releaseEngines(keep: .nemotron)
        case .orukeet:             await releaseEngines(keep: .orukeet)
        case .cloud, .unavailable: await releaseEngines(keep: .none)
        }
        guard await isCurrentGeneration(gen) else { return }

        switch plan {
        case .cloud, .unavailable:
            return  // nothing to load; UI already set
        case .parakeet:
            do {
                try await parakeet.ensureLoaded()
                await finishLoad(gen, model: .ready, status: "\(LocalEngine.parakeet.displayName) ready")
            } catch {
                await finishLoad(gen, model: .none, status: "\(LocalEngine.parakeet.displayName) failed: \(error.localizedDescription)")
            }
        case .nemotron:
            do {
                try await nemotron.ensureLoaded()
                await finishLoad(gen, model: .ready, status: "\(LocalEngine.nemotron.displayName) ready")
            } catch {
                await finishLoad(gen, model: .none, status: "\(LocalEngine.nemotron.displayName) failed: \(error.localizedDescription)")
            }
        case .orukeet:
            do {
                try await orukeet.ensureLoaded()
                await finishLoad(gen, model: .ready, status: "\(LocalEngine.orukeet.displayName) ready")
            } catch {
                await finishLoad(gen, model: .none, status: "\(LocalEngine.orukeet.displayName) failed: \(error.localizedDescription)")
            }
        }
    }

    // Unloads every engine except the one being kept, freeing its RAM/ANE footprint.
    private func releaseEngines(keep: ActiveEngine) async {
        if keep != .parakeet { await parakeet.unload() }
        if keep != .nemotron { await nemotron.unload() }
        if keep != .orukeet { await orukeet.unload() }
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
    // works - the transcribe path reloads on demand (ensureLoaded / is_loaded).
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
        // A new press supersedes a dictation that is still transcribing or rewriting.
        if state.transcribing || state.rewriting { cancelTranscription() }
        guard state.canRecord else { return }
        cancelIdleRelease()
        let liveSink = shouldStream(smart: smart) ? beginStreamingSession() : nil
        recordingGeneration &+= 1
        let generation = recordingGeneration
        statusBeforeRecording = state.status
        state.beginRecording(hotkey: hotkey, smart: smart)
        state.status = "Recording..."
        AppRecordingState.shared.isRecording = true
        FloatingPillController.shared.show(state: .recording)
        startRecordingWatchdog()
        captureQueue.async { [weak self, recorder] in
            do {
                try recorder.start(liveSink: liveSink)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { CorrectionLearner.shared.dictationStarted(generation: generation) }
                }
            } catch {
                DispatchQueue.main.async { self?.captureFailed(error, generation: generation) }
            }
        }
    }

    // Unwinds a recording whose microphone never started. A key release that already moved it on
    // to transcribing finds nothing recorded and finishes quietly, so the reason shown is this one.
    private func captureFailed(_ error: Error, generation: Int) {
        guard generation == recordingGeneration else { return }
        if state.recording {
            cancelRecordingWatchdog()
            state.cancel()
            applyPendingHotkeySetup()
            AppRecordingState.shared.isRecording = false
            FloatingPillController.shared.hide()
            if let engine = streamingEngine {
                liveInserter.cancel()
                tearDownStreamingSession()
                Task.detached { await engine.cancel() }
            }
        }
        // Before the first grant there is no TapTalk entry in System Settings to switch on yet.
        if case .permissionDenied? = error as? AudioCaptureError,
           AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            state.status = "Microphone not allowed yet - click Allow on the Record page"
        } else {
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    // Waits behind any start still queued, so a fast release never stops a capture before it began.
    private func stopCapture(_ mode: DictationRecorder.StopMode) async throws -> RecordedAudio {
        await withCheckedContinuation { continuation in captureQueue.async { continuation.resume() } }
        return try await recorder.stop(mode)
    }

    // Whether the current recording should stream live text. Smart Mode opts out - the LLM
    // rewrite needs the full transcript - and the cloud engine does not support streaming.
    // Also requires the EOU 120M realtime model to be installed; without the EOU realtime
    // model, fall back to whole-clip transcription.
    private func shouldStream(smart: Bool) -> Bool {
        settings.streamingEnabled
            && settings.transcriptionEngine == .local
            && settings.localEngine.supportsStreaming
            && !smart
            && EouStreamingEngine.isInstalled()
    }

    // Boots the streaming engine and returns the live sink that feeds it. The recorder starts with
    // the sink attached, so the engine's FIFO holds audio from the first sample while the model
    // loads on a cold start. Updates land on the main actor and drive both the LiveInserter (live
    // typing) and the UI preview.
    private func beginStreamingSession() -> LiveSink {
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

        streamConsumerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start(sampleRate: Double(SpeechTrim.sampleRate))
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

        // Yielding into AsyncStream is sync and order-preserving - no Task scheduling race per buffer.
        let continuation = engine.inputContinuation
        return { buffer in continuation.yield(buffer) }
    }

    private func tearDownStreamingSession() {
        // Idempotent: a double-call (cancel arriving while error path also tears down)
        // becomes a no-op once the session flags are already cleared.
        guard state.streamingActive || streamingEngine != nil || streamConsumerTask != nil else { return }
        streamConsumerTask?.cancel()
        streamConsumerTask = nil
        streamingEngine = nil
        state.streamingActive = false
        state.streamingConfirmed = ""
        state.streamingVolatile = ""
    }

    // Force-stops a recording that outlives the max duration - a final safety net
    // against a missed key-release leaving the app stuck in recording.
    private func startRecordingWatchdog() {
        recordingWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.recording else { return }
            self.stopAndTranscribe()
        }
        recordingWatchdog = work
        let limit = settings.hotkeyMode == .toggle ? toggleRecordingLimit : holdRecordingLimit
        DispatchQueue.main.asyncAfter(deadline: .now() + limit, execute: work)
    }

    private func applyPendingHotkeySetup() {
        if hotkeySetupPending { setupHotkey() }
    }

    private func cancelRecordingWatchdog() {
        recordingWatchdog?.cancel()
        recordingWatchdog = nil
    }

    /// Silently: a shortcut ended the press; no status, and live-typed text stays, since the
    /// shortcut already acted on the target app and backspacing could delete the wrong text.
    func cancelRecording(silently: Bool = false) {
        guard state.recording else { return }
        cancelRecordingWatchdog()
        // Reset UI/state first; tear the audio stream down off the main thread. A slow
        // CoreAudio pause (start->pause race) used to block this method and leave
        // the app stuck in the .recording phase.
        state.cancel()
        state.status = silently ? statusBeforeRecording : "Cancelled"
        AppRecordingState.shared.isRecording = false
        applyPendingHotkeySetup()
        FloatingPillController.shared.hide()
        scheduleIdleRelease()

        // Streaming session: backspace whatever was typed live, then tear down.
        // Capture the engine locally then clear `streamingEngine` immediately (via teardown) so
        // a concurrent error path can't re-touch the same instance during the detached cancel.
        let activeStreamingEngine = streamingEngine
        if activeStreamingEngine != nil {
            if silently { liveInserter.abandon() } else { liveInserter.cancel() }
            tearDownStreamingSession()
        }
        Task.detached { [self, activeStreamingEngine] in
            _ = try? await stopCapture(.discard)
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
        applyPendingHotkeySetup()
        FloatingPillController.shared.show(state: .transcribing)

        // Streaming session: text was typed live; just finalize, reconcile, and clean up.
        if let engine = streamingEngine {
            // Clear instance var immediately so a concurrent cancelRecording can't re-touch
            // this engine while the detached finish() is in flight.
            self.streamingEngine = nil
            let dictionaryRules = settings.dictionaryRules
            let learnedRules = MainActor.assumeIsolated { LearnedCorrections.shared.rules }
            let hotkeyTriggeredLocal = hotkeyTriggered
            transcribeTask = Task.detached { [weak self] in
                guard let self else { return }
                // Discard still flushes the final audio into the EOU FIFO before finish() drains it.
                _ = try? await self.stopCapture(.discard)
                do {
                    let final = try await engine.finish()
                    let processed = learnedRules.apply(dictionaryRules.apply(final))
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let typed = self.liveInserter.commit(processed)
                        // Tear down streaming flags first so the final-transcript card shows
                        // without a one-frame overlap with the streaming preview.
                        self.tearDownStreamingSession()
                        if processed.isEmpty {
                            self.state.finish()
                            self.state.status = self.tooShortStatus
                            FloatingPillController.shared.hide()
                        } else {
                            self.state.transcriptText = processed
                            self.state.transcriptLang = "auto"
                            self.state.transcriptMs = 0
                            self.state.audioDuration = 0
                            self.state.finish()
                            self.state.status = "Done"
                            // Fallback: live typing was dropped (secure input / focus moved) -
                            // paste the final utterance so it isn't silently lost. Fires
                            // regardless of how recording was triggered.
                            if !typed {
                                PasteService.paste(processed)
                            }
                            CorrectionLearner.shared.didPaste(processed)
                            if hotkeyTriggeredLocal {
                                FloatingPillController.shared.show(
                                    state: CorrectionLearner.shared.takeNotice(generation: self.recordingGeneration).map(PillState.notice) ?? .done
                                )
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

        let lang        = settings.selectedLanguage
        let engine      = settings.transcriptionEngine
        let localEngine = settings.localEngine
        let cloudModel  = settings.cloudModel
        let apiKey     = settings.apiKey
        let dictionaryRules = settings.dictionaryRules
        let learnedRules = MainActor.assumeIsolated { LearnedCorrections.shared.rules }
        let llmEnabled = settings.llmEnabled
        let llmBackend = settings.llmBackend
        let llmClient  = makeLLMClient(settings: settings)

        // The rewrite runs only when the smart hotkey asked for it and there is something to do -
        // an enabled mode, or a script conversion the transcript actually needs. Both are opt-in,
        // so the smart hotkey is a no-op until the user asks for one.
        let rewriteOptions = smartMode ? settings.rewriteOptions : []
        let hindiScript = settings.hindiScript

        // Recording is allowed while the engine loads; transcribe waits for that load to land
        // rather than starting a second one beside it.
        let pendingLoad = engineTask

        var trace = LatencyTrace()

        transcribeTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let audio = try await self.stopCapture(.transcribe)
                trace.mark("audio")
                await pendingLoad?.value

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
                } else if localEngine == .nemotron {
                    let out = try await self.nemotron.transcribe(samples: audio.samples, language: lang)
                    result = TranscriptionResult(text: out.text, language: out.language, durationMs: out.processingMs)
                } else if localEngine == .orukeet {
                    let out = try await self.orukeet.transcribe(samples: audio.samples)
                    // Orukeet auto-detects (EU); do not fabricate a specific language label.
                    result = TranscriptionResult(text: out.text, language: "auto", durationMs: out.processingMs)
                } else {
                    let out = try await self.parakeet.transcribe(samples: audio.samples)
                    // Parakeet auto-detects (EU); don't fabricate a specific language label.
                    result = TranscriptionResult(text: out.text, language: "auto", durationMs: out.processingMs)
                }

                if Task.isCancelled { return }
                trace.mark("asr")

                var processed = dictionaryRules.apply(result.text)

                // Script conversion is its own reason to call the model - a user who picked Roman
                // should get Roman without also having to enable a rewrite mode.
                let appContext = await MainActor.run { AppContextService.currentContext() }
                let romanize = smartMode && AppContextService.shouldRomanize(
                    processed,
                    script: hindiScript,
                    transcriptionEngine: engine,
                    localEngine: localEngine,
                    language: lang
                )
                let wantsRewrite = (!rewriteOptions.isEmpty || romanize) && llmEnabled
                let llmMissingForSmart = wantsRewrite && llmClient == nil && llmBackend == .local

                var rewriteError: String?
                if wantsRewrite, let client = llmClient, !processed.isEmpty {
                    await MainActor.run {
                        self.state.beginRewriting()
                        FloatingPillController.shared.show(state: .rewriting)
                    }
                    let prompt = AppContextService.systemPrompt(
                        context: appContext, options: rewriteOptions, romanize: romanize)
                    AppContextService.logResolvedContext(appContext, options: rewriteOptions)
                    do {
                        processed = try await PostProcessingService.rewrite(processed, systemPrompt: prompt, client: client)
                    } catch {
                        rewriteError = error.localizedDescription
                    }
                    trace.mark("llm")
                }

                // Learned fixes apply to exactly the kind of text they were learned from: what was pasted.
                processed = learnedRules.apply(processed)

                // Snapshot before crossing to the main actor - the closure must not capture
                // the mutable locals it was still writing to a moment ago.
                let finalTrace = trace
                let finalText = processed
                let finalError = rewriteError

                await MainActor.run {
                    guard !Task.isCancelled else { return }

                    // Guard on the final text (post dictionary/rewrite) so an empty result
                    // never gets pasted as a blank transcript.
                    if finalText.isEmpty {
                        self.state.finish()
                        self.state.status = self.tooShortStatus
                        FloatingPillController.shared.hide()
                    } else {
                        self.state.transcriptText = finalText
                        self.state.transcriptLang = result.language
                        self.state.transcriptMs   = result.durationMs
                        self.state.audioDuration  = audio.speechSeconds
                        self.state.finish()
                        if let err = finalError {
                            self.state.status = "Smart rewrite failed: \(err)"
                        } else if llmMissingForSmart {
                            self.state.status = "Local model not installed - pasted transcript only"
                        } else {
                            self.state.status = "Done"
                        }
                        if hotkeyTriggered {
                            PasteService.paste(finalText)
                            CorrectionLearner.shared.didPaste(finalText)
                            finalTrace.finish("paste")
                            FloatingPillController.shared.show(
                                    state: CorrectionLearner.shared.takeNotice(generation: self.recordingGeneration).map(PillState.notice) ?? .done
                                )
                        } else {
                            FloatingPillController.shared.hide()
                        }
                    }
                    self.scheduleIdleRelease()
                }
            } catch {
                // notRecording: the microphone never started and captureFailed already said why.
                let captureNeverStarted = (error as? AudioCaptureError) == .notRecording
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.state.finish()
                    if !captureNeverStarted { self.state.status = "Error: \(error.localizedDescription)" }
                    FloatingPillController.shared.hide()
                    self.scheduleIdleRelease()
                }
            }
        }
    }

    /// Registers (or re-registers) the global hotkey with the current key code.
    /// Safe to call multiple times - unregisters first.
    /// Deferred during active recording (user holding key) and applied when it ends;
    /// transcribing/rewriting must not block because the tap may need re-creation after invalidation.
    func setupHotkey() {
        guard !state.recording else { hotkeySetupPending = true; return }
        hotkeySetupPending = false
        guard PermissionService.isAccessibilityTrusted else {
            state.hotkeyActive = false
            // A new grant may need its own restart, so an earlier attempt no longer counts.
            MainActor.assumeIsolated { PermissionService.shared.clearRestartAttempt() }
            startPermissionPoller()
            return
        }

        HotkeyService.shared.unregister()
        HotkeyService.shared.setKeyCode(settings.hotkeyCode)
        // Smart Mode's one switch arms its key, so setting Smart Mode up needs no second trip. A Smart key
        // equal to the dictation key would never fire (the tap matches the dictation key first); Settings
        // flags that pair instead.
        let smartArmed = settings.llmEnabled && settings.smartHotkeyCode != settings.hotkeyCode
        HotkeyService.shared.setSmartKeyCode(smartArmed ? settings.smartHotkeyCode : nil)
        gesture = HotkeyGesture(mode: settings.hotkeyMode)
        HotkeyService.shared.register { [weak self] input in self?.handleHotkeyInput(input) }

        state.hotkeyActive = HotkeyService.shared.isTapAlive
        // tapCreate can keep failing after a grant until the process restarts. A grant the tap cannot
        // use yet is offered a relaunch on the setup card, never another reset of a valid grant.
        state.hotkeyNeedsRestart = !state.hotkeyActive
        if state.hotkeyActive { MainActor.assumeIsolated { PermissionService.shared.clearRestartAttempt() } }
        permissionPoller?.invalidate()
        permissionPoller = nil
    }

    private var tooShortStatus: String {
        settings.hotkeyMode == .toggle ? "Too short" : "Too short - hold longer"
    }

    private func handleHotkeyInput(_ input: GestureInput) {
        switch gesture.handle(input, isRecording: state.recording) {
        case .start(let id):
            startRecording(hotkey: true, smart: id == .smart)
            if id == .smart { prewarmRewrite() }
        case .stop:
            stopAndTranscribe()
        case .cancel:
            cancelRecording()
        case .cancelShortcut:
            cancelRecording(silently: true)
        case .pauseLiveTyping, nil:
            break
        }
    }

    private func startPermissionPoller() {
        guard permissionPoller == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard PermissionService.isAccessibilityTrusted else { return }
            DispatchQueue.main.async {
                // setupHotkey skips during a recording; retry on the next tick instead of reading that as dead.
                guard let self, !self.state.recording else { return }
                self.setupHotkey()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPoller = timer
    }
}
