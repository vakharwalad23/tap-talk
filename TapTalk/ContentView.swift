import SwiftUI

struct ContentView: View {
    @State private var selectedTab = "main"
    @State private var recorder = Recorder()
    @State private var transcriber = Transcriber()
    @State private var manager: ModelManager
    @State private var recording = false
    @State private var status = "Ready"
    @State private var transcriptText = ""
    @State private var modelLoaded = false

    init() {
        let dir = Self.modelsDirectory()
        _manager = State(initialValue: ModelManager(modelsDir: dir))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            mainTab
                .tabItem { Label("Record", systemImage: "mic") }
                .tag("main")

            modelsTab
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
                .tag("models")
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { autoLoadModel() }
    }

    // MARK: - Main Tab

    private var mainTab: some View {
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

            if modelLoaded {
                Button(recording ? "Stop" : "Record") {
                    toggleRecording()
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(recording ? .red : .accentColor)
            } else {
                Text("Download a model in the Models tab to start")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.title2)
                .fontWeight(.bold)

            ModelDownloader(manager: manager) {
                autoLoadModel()
            }
        }
        .padding(24)
    }

    // MARK: - Recording

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
                let result = try transcriber.transcribe(samples: audio.samples, language: nil)
                await MainActor.run {
                    transcriptText = result.text
                    status = String(format: "Done in %dms | %@ | %.1fs audio",
                                    result.durationMs, result.language, audio.durationSecs)
                }
            } catch {
                await MainActor.run {
                    status = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Model Loading

    private func autoLoadModel() {
        let installed = manager.installedTiers()
        guard let tier = installed.first else {
            modelLoaded = false
            status = "No models installed"
            return
        }

        status = "Loading model..."
        Task.detached {
            do {
                try transcriber.loadModel(tier: tier, modelsDir: Self.modelsDirectory())
                await MainActor.run {
                    modelLoaded = true
                    let name = availableTiers().first(where: { $0.id == tier })?.name ?? "Unknown"
                    status = "\(name) model loaded"
                }
            } catch {
                await MainActor.run {
                    status = "Load failed: \(error.localizedDescription)"
                }
            }
        }
    }

    static func modelsDirectory() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("talk.tap.app/models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
