import SwiftUI
import Carbon.HIToolbox

struct RecordView: View {
    let recorder: Recorder
    let transcriber: Transcriber
    let manager: ModelManager

    @StateObject private var state = RecordingState()
    @ObservedObject private var settings = SettingsStore.shared
    @State private var installedTiers: [UInt8] = []
    @State private var transcribeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ModelTierPicker(selectedTier: $settings.selectedTier, installedTiers: installedTiers)
                LanguagePicker(selectedLanguage: $settings.selectedLanguage)
            }
            .disabled(state.recording || state.loadingModel || state.transcribing)

            Spacer()

            Waveform(isRecording: state.recording)

            Text(state.status)
                .font(.callout)
                .foregroundStyle(state.recording ? AppTheme.danger : AppTheme.secondary)
                .frame(height: 20)

            if !state.transcriptText.isEmpty {
                TranscriptDisplay(
                    text: state.transcriptText,
                    language: state.transcriptLang,
                    durationMs: state.transcriptMs,
                    audioDuration: state.audioDuration
                )
            }

            Spacer()

            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: state.recording ? "stop.fill" : "mic.fill")
                    Text(state.recording ? "Stop" : "Record")
                }
                .frame(width: 120)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(state.recording ? AppTheme.danger : AppTheme.accent)
            .controlSize(.large)
            .disabled(!state.canRecord && !state.recording)

            Button("Cancel") { cancelRecording() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()

            HStack(spacing: 4) {
                Image(systemName: state.hotkeyActive ? "keyboard.fill" : "keyboard")
                Text(state.hotkeyActive
                     ? "Hotkey active (\(keyLabel))"
                     : "\(keyLabel) push-to-talk")
            }
            .font(.caption)
            .foregroundColor(state.hotkeyActive ? AppTheme.success : AppTheme.tertiary)
        }
        .padding(24)
        .background(AppTheme.windowBg)
        .onAppear {
            refresh()
            registerHotkey()
        }
        .onDisappear {
            HotkeyService.shared.unregister()
        }
        .onChange(of: settings.selectedTier, perform: { _ in loadSelectedTier() })
    }

    private func refresh() {
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

    private func loadSelectedTier() {
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
                try transcriber.loadModel(tier: tier, modelsDir: ContentView.modelsDirectory())
                await MainActor.run {
                    state.loadingModel = false
                    state.modelReady = true
                    state.status = "\(tierName) ready"
                }
            } catch {
                await MainActor.run {
                    state.loadingModel = false
                    state.status = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleRecording() {
        if state.recording {
            stopAndTranscribe()
        } else {
            state.hotkeyTriggered = false
            startRecording()
        }
    }

    private func startRecording() {
        guard state.canRecord else { return }

        if state.transcribing {
            cancelTranscription()
        }

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

    private func cancelRecording() {
        guard state.recording else { return }
        state.recording = false
        _ = try? recorder.stop()
        state.status = "Cancelled"
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.hide()
    }

    private func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        state.transcribing = false
        state.cancelled = true
    }

    private func stopAndTranscribe() {
        guard state.recording else { return }
        state.recording = false
        state.transcribing = true
        state.cancelled = false
        state.status = "Transcribing..."
        AppRecordingState.shared.isRecording = false
        FloatingPillController.shared.show(state: .transcribing)

        let lang = settings.selectedLanguage
        let engine = settings.transcriptionEngine
        let cloudModel = settings.cloudModel
        let apiKey = settings.apiKey

        transcribeTask = Task.detached {
            do {
                let audio = try recorder.stop()

                if Task.isCancelled {
                    await MainActor.run {
                        state.transcribing = false
                        state.status = "Cancelled"
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
                    result = try transcriber.transcribe(
                        samples: audio.samples,
                        language: lang
                    )
                }

                await MainActor.run {
                    guard !state.cancelled else { return }
                    state.transcribing = false
                    if result.text.isEmpty {
                        state.status = "Too short — hold longer"
                    } else {
                        state.transcriptText = result.text
                        state.transcriptLang = result.language
                        state.transcriptMs = result.durationMs
                        state.audioDuration = audio.durationSecs
                        state.status = "Done"
                        if state.hotkeyTriggered {
                            PasteService.paste(result.text)
                            FloatingPillController.shared.show(state: .done)
                        } else {
                            FloatingPillController.shared.hide()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard !state.cancelled else { return }
                    state.transcribing = false
                    state.status = "Error: \(error.localizedDescription)"
                    FloatingPillController.shared.hide()
                }
            }
        }
    }

    private var keyLabel: String {
        switch Int(settings.hotkeyCode) {
        case kVK_RightCommand: return "Right ⌘"
        case kVK_RightOption:  return "Right ⌥"
        case kVK_RightControl: return "Right ⌃"
        case kVK_RightShift:   return "Right ⇧"
        case kVK_Command:      return "Left ⌘"
        case kVK_Option:       return "Left ⌥"
        case kVK_Control:      return "Left ⌃"
        case kVK_Shift:        return "Left ⇧"
        default:               return "Key \(settings.hotkeyCode)"
        }
    }

    private func registerHotkey() {
        guard AccessibilityService.hasPermission else {
            AccessibilityService.requestPermission()
            return
        }

        HotkeyService.shared.setKeyCode(settings.hotkeyCode)
        let st = state
        HotkeyService.shared.register(
            keyDown: {
                if st.transcribing {
                    cancelTranscription()
                }
                st.hotkeyTriggered = true
                startRecording()
            },
            keyUp: {
                if st.recording {
                    stopAndTranscribe()
                }
            }
        )
        state.hotkeyActive = true
    }
}
