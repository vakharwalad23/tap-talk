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
    @State private var shimmerOffset: Double = -1
    @State private var dotPhase: Double = 0
    @State private var timer: Timer?

    private let barCount = 7
    private let barFreqs: [Double] = [1.8, 2.4, 1.5, 2.9, 1.2, 2.1, 3.2]
    private let barPhases: [Double] = [0, 0.8, 1.6, 0.4, 2.0, 1.2, 0.3]

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 26)
                .fill(pillBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(pillBorder, lineWidth: 1.5)
                )
                // Red glow while recording
                .shadow(
                    color: pillState == .recording
                        ? AppTheme.danger.opacity(0.4)
                        : Color.clear,
                    radius: 12,
                    x: 0, y: 4
                )

            // Content
            pillContent
        }
        .frame(width: 200, height: 52)
        .scaleEffect(pillState == .hidden ? 0.6 : 1.0)
        .opacity(pillState == .hidden ? 0 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: pillState == .hidden)
        .onAppear { startAnimations() }
        .onDisappear { stopAnimations() }
        .onChange(of: pillState) { _ in
            if pillState == .hidden { stopAnimations() } else { startAnimations() }
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
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.danger)
                        .frame(width: 3, height: barHeight(index: i))
                        .animation(.easeInOut(duration: 0.08), value: phase)
                }
            }

        case .transcribing:
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppTheme.primary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotScale(index: i))
                        .animation(.easeInOut(duration: 0.4).delay(Double(i) * 0.15), value: dotPhase)
                }
            }

        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                Text("Pasted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
            }
        }
    }

    // MARK: Helpers

    private func barHeight(index: Int) -> CGFloat {
        guard pillState == .recording else { return 4 }
        let freq = barFreqs[index]
        let ph = barPhases[index]
        let normalized = sin(phase * freq + ph) * 0.5 + 0.5
        return CGFloat(4 + normalized * 24)
    }

    private func dotScale(index: Int) -> CGFloat {
        let offset = Double(index) * 0.33
        let value = sin(dotPhase + offset * .pi * 2) * 0.5 + 0.5
        return CGFloat(0.6 + value * 0.6)
    }

    private var pillBackground: Color {
        switch pillState {
        case .recording:    return Color(red: 0.12, green: 0.06, blue: 0.06)
        case .transcribing: return Color(red: 0.08, green: 0.08, blue: 0.10)
        case .done:         return AppTheme.windowBg
        case .hidden:       return Color.clear
        }
    }

    private var pillBorder: Color {
        switch pillState {
        case .recording:    return AppTheme.danger.opacity(0.5)
        case .transcribing: return Color.white.opacity(0.12)
        case .done:         return AppTheme.success.opacity(0.6)
        case .hidden:       return Color.clear
        }
    }

    private func startAnimations() {
        stopAnimations()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            phase += 0.04
            dotPhase += 0.08
        }
    }

    private func stopAnimations() {
        timer?.invalidate()
        timer = nil
    }
}
