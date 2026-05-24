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
    // Plain var (not @Published): updated ~30 Hz from the audio thread's main hop and
    // read by the 60 fps render timer, so it must not trigger a body re-eval per sample.
    var level: Float = 0
}

struct PillView: View {
    @ObservedObject var holder: PillStateHolder

    @State private var phase: Double = 0
    @State private var displayLevel: CGFloat = 0
    @State private var timer: Timer?

    private var pillState: PillState { holder.state }

    // Maps raw mic RMS (~0.0–0.3) into a 0–1 animation range.
    private let levelGain: Float = 12

    private let recColor   = Color(red: 1.0,  green: 0.30, blue: 0.26)
    private let workColor  = Color.white.opacity(0.85)
    private let smartColor = Color(red: 0.62, green: 0.48, blue: 1.0)

    // Active capsule is fixed height — the helix swells, never the box.
    private let capsuleHeight: CGFloat = 30

    private var capsuleWidth: CGFloat {
        switch pillState {
        case .recording, .transcribing: return 96
        case .rewriting:                return 124
        case .done:                     return 104
        case .idle, .hidden:            return 0
        }
    }

    var body: some View {
        ZStack {
            switch pillState {
            case .hidden:
                EmptyView()

            case .idle:
                // resting line — a thick, long bar under nothing, Wispr-style
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 54, height: 4)
                    .transition(.opacity)

            default:
                ZStack {
                    Capsule()
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
                        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                    activeContent
                }
                .frame(width: capsuleWidth, height: capsuleHeight)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 2)
            }
        }
        .frame(width: 156, height: 40)
        .animation(.spring(response: 0.3, dampingFraction: 0.74), value: pillState)
        .onAppear { syncTimer(pillState) }
        .onDisappear { stopTimer() }
        .onChange(of: holder.state) { newState in
            syncTimer(newState)
            if newState != .recording { displayLevel = 0 }
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch pillState {
        case .recording:
            // helix is always big; voice pushes it from a tall baseline to full swing
            DNAHelixView(phase: phase, amplitude: 0.6 + 0.4 * displayLevel, color: recColor)
                .frame(width: 76, height: 22)

        case .transcribing:
            DNAHelixView(phase: phase, amplitude: 0.4, color: workColor)
                .frame(width: 76, height: 22)

        case .rewriting:
            HStack(spacing: 7) {
                DNAHelixView(phase: phase, amplitude: 0.4, color: smartColor)
                    .frame(width: 44, height: 20)
                Text("Rewriting")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.success)
                Text("Pasted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

        case .idle, .hidden:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch pillState {
        case .recording:    return recColor.opacity(0.45)
        case .transcribing: return Color.white.opacity(0.14)
        case .rewriting:    return smartColor.opacity(0.4)
        case .done:         return AppTheme.success.opacity(0.55)
        case .idle, .hidden: return .clear
        }
    }

    // Phase advances faster while processing to read as "working".
    private func phaseStep(_ state: PillState) -> Double {
        switch state {
        case .recording:               return 0.13
        case .transcribing, .rewriting: return 0.24
        default:                        return 0
        }
    }

    private func syncTimer(_ state: PillState) {
        switch state {
        case .recording, .transcribing, .rewriting: startTimer()
        default: stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            phase += phaseStep(holder.state)
            let target = CGFloat(min(1, max(0, holder.level * levelGain)))
            displayLevel += (target - displayLevel) * 0.25
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// Two dot strands weaving in sine, π out of phase so they cross like a DNA helix.
// `amplitude` (0–1) scales the vertical swing; the container size is fixed.
private struct DNAHelixView: View {
    let phase: Double
    let amplitude: CGFloat
    let color: Color

    private let dotCount = 14

    var body: some View {
        Canvas { ctx, size in
            let cy = size.height / 2
            let maxAmp = max(0, size.height / 2 - 2)
            let amp = maxAmp * min(1, max(0, amplitude))
            let waves = 1.6
            let r: CGFloat = 1.7

            for i in 0..<dotCount {
                let t = dotCount > 1 ? Double(i) / Double(dotCount - 1) : 0
                let x = size.width * CGFloat(t)
                let angle = t * waves * 2 * .pi + phase
                let yA = cy + amp * CGFloat(sin(angle))
                let yB = cy + amp * CGFloat(sin(angle + .pi))

                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: yA - r, width: 2 * r, height: 2 * r)),
                    with: .color(color)
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: yB - r, width: 2 * r, height: 2 * r)),
                    with: .color(color.opacity(0.5))
                )
            }
        }
    }
}
