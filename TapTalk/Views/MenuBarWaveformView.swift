import SwiftUI

struct MenuBarWaveformView: View {
    let isRecording: Bool

    private let idleHeights: [CGFloat] = [4, 10, 7, 12, 5]
    private let barFreqs: [Double] = [1.8, 2.6, 1.4, 3.0, 2.2]
    private let barPhases: [Double] = [0, 0.9, 1.8, 0.5, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .frame(width: 3, height: barH(i, t: t))
                        .foregroundStyle(isRecording ? Color.primary : Color.primary.opacity(0.4))
                }
            }
            .frame(width: 22, height: 16)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
    }

    private func barH(_ i: Int, t: Double) -> CGFloat {
        if !isRecording { return idleHeights[i] }
        let freq = barFreqs[i]
        let phase = barPhases[i]
        let norm = sin(t * freq + phase) * 0.5 + 0.5
        return CGFloat(3 + norm * 13)
    }
}
