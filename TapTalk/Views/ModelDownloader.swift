import SwiftUI

struct ModelDownloader: View {
    let manager: ModelManager
    let onModelChanged: () -> Void

    @State private var installedTiers: Set<UInt8> = []
    @State private var downloading: UInt8? = nil
    @State private var progress: Double = 0
    @State private var downloadedMB: Double = 0
    @State private var totalMB: Double = 0

    private let tiers = availableTiers()

    var body: some View {
        VStack(spacing: 8) {
            ForEach(tiers, id: \.id) { tier in
                tierCard(tier)
            }
        }
        .onAppear { refreshInstalled() }
    }

    @ViewBuilder
    private func tierCard(_ tier: ModelTierInfo) -> some View {
        let installed = installedTiers.contains(tier.id)
        let isDownloading = downloading == tier.id
        let isRecommended = tier.id == 3

        VStack(alignment: .leading, spacing: 10) {
            // Name + badge + size
            HStack(alignment: .center, spacing: 7) {
                Text(tier.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                if isRecommended {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Text(sizeLabel(tier.diskSizeMb))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            // Description + action
            HStack(alignment: .center) {
                Text(tierDescription(tier.id))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)

                Spacer()

                if isDownloading {
                    downloadingView
                } else if installed {
                    installedView(tier.id)
                } else {
                    downloadButton(tier.id)
                }
            }

            // Full-width progress bar when downloading
            if isDownloading {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: progress)
                        .tint(AppTheme.accent)
                    HStack {
                        Text(String(format: "%.0f MB of %.0f MB", downloadedMB, totalMB))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(14)
        .background(isRecommended ? AppTheme.accent.opacity(0.05) : AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isRecommended ? AppTheme.accent.opacity(0.18) : AppTheme.divider,
                    lineWidth: 1
                )
        )
    }

    private var downloadingView: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.secondary)
            Text("Downloading")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondary)
        }
    }

    private func installedView(_ tierId: UInt8) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                    .font(.system(size: 13))
                Text("Installed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.success)
            }

            Button {
                deleteModel(tierId)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
            }
            .buttonStyle(.plain)
        }
    }

    private func downloadButton(_ tierId: UInt8) -> some View {
        Button("Download") { downloadModel(tierId) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppTheme.divider)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(downloading != nil)
            .opacity(downloading != nil ? 0.4 : 1)
    }

    private func tierDescription(_ id: UInt8) -> String {
        switch id {
        case 1: return "Fastest · Good for quick notes"
        case 2: return "Balanced speed and accuracy"
        case 3: return "Best speed/accuracy ratio"
        case 4: return "Maximum accuracy · Slowest"
        default: return ""
        }
    }

    private func sizeLabel(_ mb: UInt32) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000) : "\(mb) MB"
    }

    private func refreshInstalled() {
        installedTiers = Set(manager.installedTiers())
    }

    private func downloadModel(_ tier: UInt8) {
        downloading = tier
        progress = 0; downloadedMB = 0; totalMB = 0

        let cb = ProgressHandler { info in
            DispatchQueue.main.async {
                if info.totalBytes > 0 {
                    self.progress = Double(info.bytesDownloaded) / Double(info.totalBytes)
                }
                self.downloadedMB = Double(info.bytesDownloaded) / 1_000_000
                self.totalMB     = Double(info.totalBytes)      / 1_000_000
                if info.done {
                    self.downloading = nil
                    self.refreshInstalled()
                    self.onModelChanged()
                }
            }
        }

        Task.detached {
            do    { try manager.download(tier: tier, callback: cb) }
            catch { await MainActor.run { downloading = nil } }
        }
    }

    private func deleteModel(_ tier: UInt8) {
        try? manager.delete(tier: tier)
        refreshInstalled()
        onModelChanged()
    }
}

private class ProgressHandler: DownloadProgressCallback {
    let handler: (DownloadProgressInfo) -> Void
    init(_ handler: @escaping (DownloadProgressInfo) -> Void) { self.handler = handler }
    func onProgress(progress: DownloadProgressInfo) { handler(progress) }
}
