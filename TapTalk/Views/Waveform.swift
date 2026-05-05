import SwiftUI

struct Waveform: View {
    let isRecording: Bool

    @State private var phase: Double = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? AppTheme.danger : AppTheme.primary.opacity(0.2))
                    .frame(width: 4, height: barHeight(index: i))
                    .animation(.easeInOut(duration: 0.3), value: isRecording)
            }
        }
        .frame(height: 32)
        .onAppear { startAnimation() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func barHeight(index: Int) -> CGFloat {
        if !isRecording { return 4 }
        let base = sin(Double(index) * 0.5 + phase) * 0.5 + 0.5
        return CGFloat(4 + base * 28)
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            phase += 0.3
        }
    }
}
