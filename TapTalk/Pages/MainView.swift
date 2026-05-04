import SwiftUI

struct MainView: View {
    let recorder: Recorder
    let transcriber: Transcriber
    let manager: ModelManager

    @State private var recording = false
    @State private var status = ""
    @State private var transcriptText = ""
    @State private var transcriptLang = ""
    @State private var transcriptMs: UInt64 = 0
    @State private var audioDuration: Float = 0
    @State private var selectedTier: UInt8 = 1
    @State private var selectedLanguage: String? = nil
    @State private var installedTiers: [UInt8] = []
    @State private var modelReady = false
    @State private var loadingModel = false

    var body: some View {
        VStack(spacing: 20) {
            // Controls row
            HStack(spacing: 12) {
                ModelTierPicker(selectedTier: $selectedTier, installedTiers: installedTiers)
                LanguagePicker(selectedLanguage: $selectedLanguage)
            }
            .disabled(recording || loadingModel)

            Spacer()

            // Waveform
            Waveform(isRecording: recording)

            // Status
            Text(status)
                .font(.callout)
                .foregroundStyle(recording ? .red : .secondary)
                .frame(height: 20)

            // Transcript
            if !transcriptText.isEmpty {
                TranscriptDisplay(
                    text: transcriptText,
                    language: transcriptLang,
                    durationMs: transcriptMs,
                    audioDuration: audioDuration
                )
            }

            Spacer()

            // Record button
            Button(action: toggleRecording) {
                HStack {
                    Image(systemName: recording ? "stop.fill" : "mic.fill")
                    Text(recording ? "Stop" : "Record")
                }
                .frame(width: 120)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(recording ? .red : .accentColor)
            .controlSize(.large)
            .disabled(!modelReady || loadingModel)
        }
        .padding(24)
        .onAppear { refresh() }
        .onChange(of: selectedTier, perform: { _ in loadSelectedTier() })
    }

    private func refresh() {
        installedTiers = manager.installedTiers().sorted()
        if let first = installedTiers.first {
            selectedTier = first
            loadSelectedTier()
        } else {
            status = "No models installed"
            modelReady = false
        }
    }

    private func loadSelectedTier() {
        guard installedTiers.contains(selectedTier) else { return }
        loadingModel = true
        modelReady = false
        let tierName = availableTiers().first(where: { $0.id == selectedTier })?.name ?? ""
        status = "Loading \(tierName)..."

        Task.detached {
            do {
                try transcriber.loadModel(tier: selectedTier, modelsDir: ContentView.modelsDirectory())
                await MainActor.run {
                    loadingModel = false
                    modelReady = true
                    status = "\(tierName) ready"
                }
            } catch {
                await MainActor.run {
                    loadingModel = false
                    status = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleRecording() {
        if recording { stopAndTranscribe() } else { startRecording() }
    }

    private func startRecording() {
        do {
            try recorder.start()
            recording = true
            status = "Recording..."
            transcriptText = ""
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        recording = false
        status = "Transcribing..."

        Task.detached {
            do {
                let audio = try recorder.stop()
                let result = try transcriber.transcribe(
                    samples: audio.samples,
                    language: selectedLanguage
                )
                await MainActor.run {
                    transcriptText = result.text
                    transcriptLang = result.language
                    transcriptMs = result.durationMs
                    audioDuration = audio.durationSecs
                    status = "Done"
                }
            } catch {
                await MainActor.run {
                    status = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
