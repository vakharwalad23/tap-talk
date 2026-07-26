import SwiftUI
import AppKit

struct AboutView: View {
    @State private var githubHovering = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("About")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TapTalk")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text("Version \(version) (\(build))")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                }

                Text("Local speech-to-text for macOS. Hold a hotkey, speak, release — your words appear wherever the cursor is. Runs entirely on-device on the Neural Engine. No account, no cloud by default.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(AppTheme.divider)

                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Engines", value: "NVIDIA Parakeet TDT · Nemotron 3.5 ASR")
                    infoRow("Runtime", value: "Core ML / Neural Engine via FluidAudio")
                    infoRow("Audio", value: "cpal · Silero VAD silence trimming")
                    infoRow("Platform", value: "macOS 14+ · Apple Silicon")
                }

                Divider().background(AppTheme.divider)

                Button {
                    if let url = URL(string: "https://github.com/vakharwalad23/tap-talk") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("View on GitHub")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(githubHovering ? AppTheme.accent : AppTheme.primary)
                    .underline(githubHovering)
                    // contentShape keeps the whole row hoverable; without it only the glyphs are.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    githubHovering = hovering
                    // set() rather than push()/pop(): a pushed cursor leaks if the view goes away
                    // while hovered, and this view is in a tab the user can switch out of.
                    (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
                }
                .onDisappear {
                    if githubHovering {
                        githubHovering = false
                        NSCursor.arrow.set()
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .background(AppTheme.windowBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)
        }
    }
}
