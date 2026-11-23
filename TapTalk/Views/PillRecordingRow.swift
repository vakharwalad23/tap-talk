import AppKit
import SwiftUI

/// Recording pill: cancel, elapsed time, live level bars, finish. Redrawn by PillView's render loop.
struct PillRecordingRow: View {
    let elapsed: TimeInterval
    let level: CGFloat
    let phase: Double

    private static let buttonSize: CGFloat = 24
    private static let barCount = 11
    // Center bars swing further than the edges, so speech reads as a waveform rather than a meter.
    private static let barProfile: [CGFloat] = (0..<barCount).map { i in
        let t = CGFloat(i) / CGFloat(barCount - 1)
        return 0.45 + 0.55 * sin(t * .pi)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { AppController.shared.cancelRecording() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel recording")

            Text(Self.clock(elapsed))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(nsColor: .systemRed))
                .accessibilityHidden(true)

            bars
                .accessibilityHidden(true)

            Button { AppController.shared.stopAndTranscribe() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(Circle().fill(Color.primary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Finish")
            .accessibilityLabel("Finish and paste")
        }
        .padding(.horizontal, (PillView.capsuleHeight - Self.buttonSize) / 2)
    }

    // Each bar sways a little with phase, scaled by level: silence draws a flat line.
    private var bars: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                let sway = 0.7 + 0.3 * sin(phase * 9 + Double(i) * 1.3)
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 2.5, height: 2.5 + 15 * level * Self.barProfile[i] * CGFloat(sway))
            }
        }
        .frame(height: 18)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
