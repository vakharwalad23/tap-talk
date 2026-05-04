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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tiers, id: \.id) { tier in
                tierRow(tier)
                if tier.id != tiers.last?.id {
                    Divider()
                }
            }
        }
        .onAppear { refreshInstalled() }
    }

    @ViewBuilder
    private func tierRow(_ tier: ModelTierInfo) -> some View {
        let installed = installedTiers.contains(tier.id)
        let isDownloading = downloading == tier.id

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.name)
                    .font(.headline)
                Text(sizeLabel(tier.diskSizeMb))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloading {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                    Text(String(format: "%.0f / %.0f MB", downloadedMB, totalMB))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if installed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Delete") {
                        deleteModel(tier.id)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            } else {
                Button("Download") {
                    downloadModel(tier.id)
                }
                .disabled(downloading != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func sizeLabel(_ mb: UInt32) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }

    private func refreshInstalled() {
        installedTiers = Set(manager.installedTiers())
    }

    private func downloadModel(_ tier: UInt8) {
        downloading = tier
        progress = 0
        downloadedMB = 0
        totalMB = 0

        let callback = ProgressHandler { info in
            DispatchQueue.main.async {
                if info.totalBytes > 0 {
                    self.progress = Double(info.bytesDownloaded) / Double(info.totalBytes)
                }
                self.downloadedMB = Double(info.bytesDownloaded) / 1_000_000
                self.totalMB = Double(info.totalBytes) / 1_000_000

                if info.done {
                    self.downloading = nil
                    self.refreshInstalled()
                    self.onModelChanged()
                }
            }
        }

        Task.detached {
            do {
                try manager.download(tier: tier, callback: callback)
            } catch {
                await MainActor.run {
                    downloading = nil
                }
            }
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

    init(_ handler: @escaping (DownloadProgressInfo) -> Void) {
        self.handler = handler
    }

    func onProgress(progress: DownloadProgressInfo) {
        handler(progress)
    }
}
