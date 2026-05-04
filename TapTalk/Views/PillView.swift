import SwiftUI

enum PillState: Equatable {
    case hidden
    case recording
    case transcribing
    case done
}

struct PillView: View {
    var pillState: PillState

    @State private var phase: Double = 0
    @State private var dotPhase: Double = 0
    @State private var timer: Timer?

    private let barCount = 7
    private let barFreqs: [Double] = [1.6, 2.5, 1.1, 3.0, 0.9, 2.3, 1.8]
    private let barPhases: [Double] = [0, 1.1, 2.2, 0.6, 1.8, 0.3, 2.7]

    var body: some View {
        ZStack {
            if pillState != .hidden {
                pillContent
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(width: 156, height: 38)
        .background(pillState == .hidden ? Color.clear : bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(
            RoundedRectangle(cornerRadius: 19)
                .stroke(pillState == .hidden ? Color.clear : borderColor, lineWidth: 1)
        )
        // shadow applied after clip so it renders outside the pill, not as a box
        .shadow(
            color: pillState == .recording
                ? Color(red: 1, green: 0.2, blue: 0.2).opacity(0.4)
                : Color.black.opacity(pillState == .hidden ? 0 : 0.18),
            radius: pillState == .recording ? 8 : 4,
            x: 0, y: pillState == .hidden ? 0 : 2
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: pillState)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: pillState) { _ in
            if pillState == .hidden { stopTimer() } else { startTimer() }
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        switch pillState {
        case .hidden:
            EmptyView()

        case .recording:
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color(red: 1, green: 0.28, blue: 0.22))
                        .frame(width: 2.5, height: barHeight(index: i))
                }
            }

        case .transcribing:
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotScale(index: i))
                }
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
        let ph = barPhases[index]
        let norm = sin(phase * freq + ph) * 0.5 + 0.5
        return CGFloat(5 + norm * 22)
    }

    private func dotScale(index: Int) -> CGFloat {
        let ph = Double(index) * .pi * 0.67
        let v = sin(dotPhase + ph) * 0.5 + 0.5
        return CGFloat(0.55 + v * 0.65)
    }

    private var bgColor: Color {
        switch pillState {
        case .recording:    return Color(red: 0.11, green: 0.04, blue: 0.04)
        case .transcribing: return Color(red: 0.10, green: 0.10, blue: 0.13)
        case .done:         return Color(red: 0.07, green: 0.15, blue: 0.08)
        case .hidden:       return .clear
        }
    }

    private var borderColor: Color {
        switch pillState {
        case .recording:    return Color(red: 1, green: 0.22, blue: 0.18).opacity(0.55)
        case .transcribing: return Color.white.opacity(0.12)
        case .done:         return AppTheme.success.opacity(0.65)
        case .hidden:       return .clear
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            phase += 0.048
            dotPhase += 0.09
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
