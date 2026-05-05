import SwiftUI

enum PillState: Equatable {
    case idle
    case hidden
    case recording
    case transcribing
    case rewriting
    case done
}

final class PillStateHolder: ObservableObject {
    @Published var state: PillState = .hidden
}

struct PillView: View {
    @ObservedObject var holder: PillStateHolder

    @State private var phase: Double = 0
    @State private var dotPhase: Double = 0
    @State private var timer: Timer?

    private var pillState: PillState { holder.state }

    private let barCount = 7
    private let barFreqs: [Double]  = [1.6, 2.5, 1.1, 3.0, 0.9, 2.3, 1.8]
    private let barPhases: [Double] = [0,   1.1, 2.2, 0.6, 1.8, 0.3, 2.7]

    var body: some View {
        ZStack {
            if pillState != .hidden {
                RoundedRectangle(cornerRadius: 19)
                    .fill(bgColor)
                    .transition(.opacity)

                pillContent
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .frame(width: 156, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(
            color: pillState == .hidden ? .clear : Color.black.opacity(0.22),
            radius: 5, x: 0, y: 2
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: pillState)
        .onAppear {
            if pillState == .recording || pillState == .transcribing || pillState == .rewriting { startTimer() }
        }
        .onDisappear { stopTimer() }
        .onChange(of: holder.state) { newState in
            switch newState {
            case .recording, .transcribing, .rewriting: startTimer()
            default: stopTimer()
            }
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        switch pillState {
        case .hidden:
            EmptyView()

        case .idle:
            // static waveform — calm snapshot showing the app is ready
            HStack(spacing: 3) {
                ForEach(Array([5, 11, 7, 15, 9, 13, 6].enumerated()), id: \.offset) { _, h in
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 2.5, height: CGFloat(h))
                }
            }

        case .recording:
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color(red: 1, green: 0.27, blue: 0.21))
                        .frame(width: 2.5, height: barHeight(index: i))
                }
            }

        case .transcribing:
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.72))
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotScale(index: i))
                }
            }

        case .rewriting:
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color(red: 0.58, green: 0.42, blue: 1.0).opacity(0.82))
                            .frame(width: 5, height: 5)
                            .scaleEffect(dotScale(index: i))
                    }
                }
                Text("Rewriting")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }

        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                Text("Pasted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        guard pillState == .recording else { return 4 }
        let freq = barFreqs[index]
        let ph   = barPhases[index]
        let norm = sin(phase * freq + ph) * 0.5 + 0.5
        return CGFloat(5 + norm * 22)
    }

    private func dotScale(index: Int) -> CGFloat {
        let ph = Double(index) * .pi * 0.67
        let v  = sin(dotPhase + ph) * 0.5 + 0.5
        return CGFloat(0.55 + v * 0.65)
    }

    private var bgColor: Color {
        switch pillState {
        case .idle:         return Color(red: 0.13, green: 0.13, blue: 0.15)
        case .recording:    return Color(red: 0.11, green: 0.04, blue: 0.04)
        case .transcribing: return Color(red: 0.10, green: 0.10, blue: 0.13)
        case .rewriting:    return Color(red: 0.10, green: 0.08, blue: 0.16)
        case .done:         return Color(red: 0.07, green: 0.15, blue: 0.08)
        case .hidden:       return .clear
        }
    }

    private var borderColor: Color {
        switch pillState {
        case .idle:         return Color.white.opacity(0.08)
        case .recording:    return Color(red: 1, green: 0.22, blue: 0.18).opacity(0.5)
        case .transcribing: return Color.white.opacity(0.11)
        case .rewriting:    return Color(red: 0.58, green: 0.42, blue: 1.0).opacity(0.4)
        case .done:         return AppTheme.success.opacity(0.6)
        case .hidden:       return .clear
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            phase    += 0.048
            dotPhase += 0.09
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
