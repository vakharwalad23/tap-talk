import SwiftUI
import TapTalkLearning

enum PillState: Equatable {
    case idle
    case hidden
    case recording
    case transcribing
    case rewriting
    case done
    /// Pasted, plus a word fix just learned or stopped, with Undo.
    case notice(LearningEvent)
    /// Transcribed while nobody was at the keyboard; the text waits in the window.
    case notPasted
}

final class PillStateHolder: ObservableObject {
    @Published var state: PillState = .hidden
    // Plain var (not @Published): updated ~30 Hz from the audio thread's main hop and
    // read by the 60 fps render timer, so it must not trigger a body re-eval per sample.
    var level: Float = 0
}

struct PillView: View {
    @ObservedObject var holder: PillStateHolder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Double = 0
    @State private var displayLevel: CGFloat = 0
    @State private var timer: Timer?

    private var pillState: PillState { holder.state }

    // Maps raw mic RMS (~0.0-0.3) into a 0-1 animation range.
    private let levelGain: Float = 12
    static let capsuleHeight: CGFloat = 32
    // Shared with FloatingPillController's notice width, which measures the same text.
    static let textPadding: CGFloat = 14

    var body: some View {
        ZStack {
            switch pillState {
            case .hidden:
                EmptyView()
            case .idle:
                PillGlass()
                    .frame(width: 43, height: 5)
                    .transition(.opacity)
            default:
                activeContent
                    .frame(height: Self.capsuleHeight)
                    .background(PillGlass())
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.74), value: pillState)
        .onAppear { syncTimer(pillState) }
        .onDisappear { stopTimer() }
        .onChange(of: holder.state) {
            syncTimer(holder.state)
            if holder.state != .recording { displayLevel = 0 }
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        switch pillState {
        case .recording:
            Capsule()
                .fill(Color(nsColor: .systemRed))
                .frame(width: 16 + 104 * displayLevel, height: 3)
                .frame(width: 120)
                .padding(.horizontal, Self.textPadding)

        case .transcribing:
            ShimmerLine(phase: phase, isAnimated: !reduceMotion)
                .frame(width: 56, height: 3)
                .padding(.horizontal, Self.textPadding)

        case .rewriting:
            label("Rewriting") {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color(nsColor: .systemPurple))
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            }

        case .done:
            label("Pasted") { checkmark }

        case .notice(let event):
            HStack(spacing: 8) {
                checkmark
                pillText(Self.noticeText(event))
                Button("Undo") {
                    CorrectionLearner.shared.undoNotice(event)
                    FloatingPillController.shared.hide()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemPurple))
            }
            .padding(.horizontal, Self.textPadding)

        case .notPasted:
            Button {
                MainWindowOpener.shared.open()
                FloatingPillController.shared.hide()
            } label: {
                label(Self.notPastedText) {
                    Image(systemName: "tray.and.arrow.down").foregroundStyle(.secondary)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

        case .idle, .hidden:
            EmptyView()
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(nsColor: .systemGreen))
    }

    private func label<Icon: View>(_ text: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 8) {
            icon().font(.system(size: 12, weight: .semibold))
            pillText(text)
        }
        .padding(.horizontal, Self.textPadding)
    }

    private func pillText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    static let notPastedText = "Not pasted - open TapTalk"

    static func noticeText(_ event: LearningEvent) -> String {
        switch event {
        case .learned(let rule): return "Learned: \(shortened(rule.from)) -> \(shortened(rule.to))"
        case .stopped(let rule): return "Stopped: \(shortened(rule.from)) -> \(shortened(rule.to))"
        }
    }

    // Keeps a long fix from stretching the pill across the screen.
    private static func shortened(_ text: String) -> String {
        text.count > 24 ? text.prefix(24) + "..." : text
    }

    // The render loop runs only while something moves; idle, done and notices cost nothing.
    private func syncTimer(_ state: PillState) {
        switch state {
        case .recording: startTimer()
        case .transcribing where !reduceMotion: startTimer()
        default: stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            phase += 1.0 / 60.0
            let target = CGFloat(min(1, max(0, holder.level * levelGain)))
            displayLevel += (target - displayLevel) * 0.25
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// A dim line with a brighter band sweeping across it about once a second.
private struct ShimmerLine: View {
    let phase: Double
    let isAnimated: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let sweep = CGFloat(phase.truncatingRemainder(dividingBy: 1.1) / 1.1)
            Capsule()
                .fill(Color.primary.opacity(isAnimated ? 0.18 : 0.35))
                .overlay(alignment: .leading) {
                    if isAnimated {
                        LinearGradient(colors: [.clear, Color.primary.opacity(0.75), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.5)
                            .offset(x: -width * 0.5 + sweep * width * 1.5)
                    }
                }
                .clipShape(Capsule())
        }
    }
}
