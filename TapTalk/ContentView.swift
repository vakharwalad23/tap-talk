import SwiftUI

struct ContentView: View {
    @State private var recorder = Recorder()
    @State private var transcriber = Transcriber()
    @State private var recording = false
    @State private var status = "Ready"
    @State private var transcriptText = ""
    @State private var modelLoaded = false
    @State private var loading = false

    private var modelsDir: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("TapTalk")
                .font(.title)
                .fontWeight(.bold)

            Text(status)
                .font(.callout)
                .foregroundStyle(recording ? .red : .secondary)

            if !transcriptText.isEmpty {
                GroupBox("Transcript") {
                    Text(transcriptText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                if !modelLoaded {
                    Button("Load Tiny Model") {
                        loadModel()
                    }
                    .disabled(loading)
                } else {
                    Button(recording ? "Stop" : "Record") {
                        toggleRecording()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .tint(recording ? .red : .accentColor)
                }
            }

            Text("Models: \(modelsDir)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(32)
        .frame(minWidth: 450, minHeight: 320)
    }

    private func loadModel() {
        loading = true
        status = "Loading model..."
        Task.detached {
            do {
                try transcriber.loadModel(tier: 1, modelsDir: modelsDir)
                await MainActor.run {
                    modelLoaded = true
                    loading = false
                    status = "Tiny model loaded. Ready to record."
                }
            } catch {
                await MainActor.run {
                    loading = false
                    status = "Load failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleRecording() {
        if recording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
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
                    language: nil
                )
                await MainActor.run {
                    transcriptText = result.text
                    status = String(
                        format: "Done in %dms | %@ | %.1fs audio",
                        result.durationMs,
                        result.language,
                        audio.durationSecs
                    )
                }
            } catch {
                await MainActor.run {
                    status = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
