import SwiftUI

struct ContentView: View {
    @State private var rustResponse = "..."
    @State private var rustInfo = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("TapTalk — Setup OK")
                .font(.title)
                .fontWeight(.bold)

            Text("Rust bridge: \(rustResponse)")
                .font(.body)
                .foregroundStyle(.secondary)

            Text(rustInfo)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            rustResponse = ping()
            rustInfo = systemInfo()
        }
    }
}
