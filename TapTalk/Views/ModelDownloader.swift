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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tiers, id: \.id) { tier in
                tierRow(tier)
                if tier.id != tiers.last?.id {
                    Divider()
                        .background(AppTheme.divider)
                }
            }
        }
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        .onAppear { refreshInstalled() }
    }

    @ViewBuilder
    private func tierRow(_ tier: ModelTierInfo) -> some View {
        let installed = installedTiers.contains(tier.id)
        let isDownloading = downloading == tier.id

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tier.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text(sizeLabel(tier.diskSizeMb))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondary)
            }

            Spacer()

            if isDownloading {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 90)
                        .tint(AppTheme.accent)
                    Text(String(format: "%.0f / %.0f MB", downloadedMB, totalMB))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondary)
                }
            } else if installed {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success)
                        .font(.system(size: 14))
                    Button("Delete") { deleteModel(tier.id) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.danger)
                }
            } else {
                Button("Download") { downloadModel(tier.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.small)
                    .disabled(downloading != nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
