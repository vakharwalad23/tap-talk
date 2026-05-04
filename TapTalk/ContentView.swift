import SwiftUI

struct ContentView: View {
    @State private var recorder = Recorder()
    @State private var recording = false
    @State private var status = "Ready"
    @State private var resultText = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("TapTalk")
                .font(.title)
                .fontWeight(.bold)

            Text(status)
                .font(.body)
                .foregroundStyle(recording ? .red : .secondary)

            if !resultText.isEmpty {
                GroupBox("Result") {
                    Text(resultText)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button(recording ? "Stop" : "Record") {
                    toggleRecording()
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(recording ? .red : .accentColor)
            }

            Text("Rust bridge: \(ping())")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(minWidth: 400, minHeight: 300)
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            recording = true
            status = "Recording..."
            resultText = ""
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        do {
            let result = try recorder.stop()
            recording = false
            status = String(
                format: "Captured %.1fs (%d samples, 16kHz mono)",
                result.durationSecs,
                result.sampleCount
            )
            resultText = "Samples: \(result.sampleCount)\nDuration: \(String(format: "%.2f", result.durationSecs))s\nVAD trimmed to speech regions"
        } catch {
            recording = false
            status = "Error: \(error.localizedDescription)"
        }
    }
}
