import SwiftUI

struct ModelDownloader: View {
    let manager: ModelManager
    let onModelChanged: () -> Void

    @State private var installedTiers: Set<UInt8> = []
    @State private var missingCoreml: Set<UInt8> = []
    @State private var downloading: UInt8? = nil
    @State private var downloadPhase: DownloadPhase = .ggml
    @State private var progress: Double = 0
    @State private var downloadedMB: Double = 0
    @State private var totalMB: Double = 0
    @State private var bannerDismissed: Bool = UserDefaults.standard.bool(forKey: bannerDismissedKey)
    @State private var coremlQueue: [UInt8] = []
    @State private var pendingCoremlRemoval: UInt8? = nil

    private static let bannerDismissedKey = "tt.coreml.banner.dismissed"
    private let tiers = availableTiers()

    private func hasCoreml(_ tierId: UInt8) -> Bool {
        installedTiers.contains(tierId) && !missingCoreml.contains(tierId)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !missingCoreml.isEmpty && !bannerDismissed {
                coremlBanner
            }
            VStack(spacing: 8) {
                ForEach(tiers, id: \.id) { tier in
                    tierCard(tier)
                }
                ParakeetCard()
            }
        }
        .onAppear { refreshInstalled() }
        .alert(
            "Remove Neural Engine optimization?",
            isPresented: Binding(
                get: { pendingCoremlRemoval != nil },
                set: { if !$0 { pendingCoremlRemoval = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingCoremlRemoval = nil }
            Button("Remove", role: .destructive) {
                if let tier = pendingCoremlRemoval { removeOptimization(tier) }
                pendingCoremlRemoval = nil
            }
        } message: {
            Text("This reclaims disk space and keeps the model fully usable — transcription just runs on the GPU instead of the Neural Engine. The model itself is not deleted.")
        }
    }

    private var coremlBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cpu.fill")
                .foregroundStyle(AppTheme.accent)
                .font(.system(size: 18))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Boost transcription speed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("Runs transcription on the Neural Engine — much faster. Trade-off: it roughly doubles each model's disk space (e.g. ~+1.2 GB for Large). You can remove it anytime to get the space back.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Optimize") { startCoremlMigration() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(downloading != nil)
                        .opacity(downloading != nil ? 0.4 : 1)

                    Button("Not now") { dismissBanner() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                        .disabled(downloading != nil)
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tierCard(_ tier: ModelTierInfo) -> some View {
        let installed = installedTiers.contains(tier.id)
        let isDownloading = downloading == tier.id
        let isRecommended = tier.id == 3

        VStack(alignment: .leading, spacing: 10) {
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
            Text(downloadPhase == .coreMl ? "Optimizing" : "Downloading")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondary)
        }
    }

    private func installedView(_ tierId: UInt8) -> some View {
        HStack(spacing: 10) {
            optimizationControl(tierId)

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
            .help("Delete model")
        }
    }

    @ViewBuilder
    private func optimizationControl(_ tierId: UInt8) -> some View {
        if hasCoreml(tierId) {
            // Optimization present — green badge that, when clicked, offers to reclaim space.
            Button { pendingCoremlRemoval = tierId } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 8))
                    Text("Neural Engine").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AppTheme.success)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AppTheme.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(downloading != nil)
            .help("Neural Engine optimization on — click to remove and reclaim disk")
        } else {
            // ggml installed but no encoder bundle — offer to add it.
            Button { enableOptimization(tierId) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bolt").font(.system(size: 8))
                    Text("Speed up").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(AppTheme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(downloading != nil)
            .help("Faster transcription via the Neural Engine. Uses more disk (~doubles the model size); removable anytime.")
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
        missingCoreml = Set(manager.installedTiersMissingCoreml())
    }

    private func downloadModel(_ tier: UInt8) {
        downloading = tier
        downloadPhase = .ggml
        progress = 0; downloadedMB = 0; totalMB = 0

        let cb = ProgressHandler { info in
            DispatchQueue.main.async {
                self.downloadPhase = info.phase
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

    private func startCoremlMigration() {
        coremlQueue = Array(missingCoreml).sorted()
        processCoremlQueue()
    }

    // Per-tier opt-in download of the Neural Engine encoder.
    private func enableOptimization(_ tier: UInt8) {
        guard downloading == nil else { return }
        coremlQueue = [tier]
        processCoremlQueue()
    }

    // Removes ONLY the Core ML encoder bundle; the ggml model stays installed.
    private func removeOptimization(_ tier: UInt8) {
        try? manager.deleteCoreml(tier: tier)
        refreshInstalled()
        onModelChanged()
    }

    private func processCoremlQueue() {
        guard let tier = coremlQueue.first else { return }
        coremlQueue.removeFirst()

        downloading = tier
        downloadPhase = .coreMl
        progress = 0; downloadedMB = 0; totalMB = 0

        let cb = ProgressHandler { info in
            DispatchQueue.main.async {
                self.downloadPhase = info.phase
                if info.totalBytes > 0 {
                    self.progress = Double(info.bytesDownloaded) / Double(info.totalBytes)
                }
                self.downloadedMB = Double(info.bytesDownloaded) / 1_000_000
                self.totalMB     = Double(info.totalBytes)      / 1_000_000
                if info.done {
                    self.downloading = nil
                    self.refreshInstalled()
                    self.processCoremlQueue()
                }
            }
        }

        Task.detached {
            do    { try manager.downloadCoremlOnly(tier: tier, callback: cb) }
            catch { await MainActor.run { downloading = nil; coremlQueue.removeAll() } }
        }
    }

    private func dismissBanner() {
        UserDefaults.standard.set(true, forKey: Self.bannerDismissedKey)
        bannerDismissed = true
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

@MainActor
private final class ParakeetDownloadModel: ObservableObject {
    @Published var installed = ParakeetEngine.isInstalled()
    @Published var downloading = false
    @Published var progress: Double = 0

    func download() {
        downloading = true
        progress = 0
        Task {
            do {
                try await ParakeetEngine.download { p in
                    Task { @MainActor in self.progress = p }
                }
                self.downloading = false
                self.installed = true
                AppController.shared.refresh()
            } catch {
                self.downloading = false
            }
        }
    }

    func remove() {
        try? ParakeetEngine.delete()
        installed = false
        AppController.shared.refresh()
    }
}

// Catalog card for the optional Parakeet engine. Download is user-initiated (never auto).
private struct ParakeetCard: View {
    @StateObject private var model = ParakeetDownloadModel()
    @State private var pendingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("Parakeet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("Optimized")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text("~490 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("Faster · English + EU · built-in punctuation")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)

                Spacer()

                if model.downloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(AppTheme.secondary)
                        Text("Downloading")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondary)
                    }
                } else if model.installed {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                                .font(.system(size: 13))
                            Text("Installed")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.success)
                        }
                        Button { pendingRemoval = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("Download") { model.download() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.divider)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if model.downloading {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: model.progress)
                        .tint(AppTheme.accent)
                    Text("\(Int(model.progress * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .alert("Remove Parakeet model?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            Text("Frees ~490 MB. You can re-download it anytime.")
        }
    }
}
