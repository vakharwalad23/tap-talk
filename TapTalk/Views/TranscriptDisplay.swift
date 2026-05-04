import SwiftUI

struct TranscriptDisplay: View {
    let text: String
    let language: String
    let durationMs: UInt64
    let audioDuration: Float

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Label(language.uppercased(), systemImage: "globe")
                Label(String(format: "%dms", durationMs), systemImage: "timer")
                Label(String(format: "%.1fs audio", audioDuration), systemImage: "waveform")

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(copied ? .green : .secondary)
                .animation(.easeInOut(duration: 0.2), value: copied)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
