import SwiftUI

struct ModelDownloader: View {
    // Download state lives in an app-lifetime singleton so progress survives navigating
    // away from the Models page and back.
    @ObservedObject private var whisper = WhisperModelDownloadManager.shared
    @State private var bannerDismissed: Bool = UserDefaults.standard.bool(forKey: bannerDismissedKey)
    @State private var pendingCoremlRemoval: UInt8? = nil

    private static let bannerDismissedKey = "tt.coreml.banner.dismissed"
    private let tiers = availableTiers()

    var body: some View {
        VStack(spacing: 12) {
            if !whisper.missingCoreml.isEmpty && !bannerDismissed {
                coremlBanner
            }
            VStack(spacing: 8) {
                // Recommended + optimized engines first, then the remaining whisper tiers.
                if let recommended = tiers.first(where: { $0.id == 3 }) {
                    tierCard(recommended)
                }
                ParakeetCard()
                EouCard()
                WhisperKitCard()
                ForEach(tiers.filter { $0.id != 3 }, id: \.id) { tier in
                    tierCard(tier)
                }
            }
        }
        .onAppear { whisper.refreshInstalled() }
        .alert(
            "Remove Neural Engine optimization?",
            isPresented: Binding(
                get: { pendingCoremlRemoval != nil },
                set: { if !$0 { pendingCoremlRemoval = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingCoremlRemoval = nil }
            Button("Remove", role: .destructive) {
                if let tier = pendingCoremlRemoval { whisper.removeOptimization(tier) }
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
                    Button("Optimize") { whisper.startCoremlMigration() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(whisper.downloading != nil)
                        .opacity(whisper.downloading != nil ? 0.4 : 1)

                    Button("Not now") { dismissBanner() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondary)
                        .disabled(whisper.downloading != nil)
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
        let installed = whisper.installedTiers.contains(tier.id)
        let isDownloading = whisper.downloading == tier.id
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
                    ProgressView(value: whisper.progress)
                        .tint(AppTheme.accent)
                    HStack {
                        Text(String(format: "%.0f MB of %.0f MB", whisper.downloadedMB, whisper.totalMB))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiary)
                        Spacer()
                        Text("\(Int(whisper.progress * 100))%")
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
            Text(whisper.downloadPhase == .coreMl ? "Optimizing" : "Downloading")
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
                whisper.deleteModel(tierId)
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
        if whisper.hasCoreml(tierId) {
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
            .disabled(whisper.downloading != nil)
            .help("Neural Engine optimization on — click to remove and reclaim disk")
        } else {
            // ggml installed but no encoder bundle — offer to add it.
            Button { whisper.enableOptimization(tierId) } label: {
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
            .disabled(whisper.downloading != nil)
            .help("Faster transcription via the Neural Engine. Uses more disk (~doubles the model size); removable anytime.")
        }
    }

    private func downloadButton(_ tierId: UInt8) -> some View {
        Button("Download") { whisper.downloadModel(tierId) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppTheme.divider)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(whisper.downloading != nil)
            .opacity(whisper.downloading != nil ? 0.4 : 1)
    }

    private func tierDescription(_ id: UInt8) -> String {
        switch id {
        case 1: return "Fastest, least accurate. Fine for short, clear notes."
        case 2: return "A good balance of speed and accuracy for everyday use."
        case 3: return "Best all-round choice — accurate and quick, 90+ languages."
        case 4: return "The most accurate, 90+ languages. Largest and slowest."
        default: return ""
        }
    }

    private func sizeLabel(_ mb: UInt32) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000) : "\(mb) MB"
    }

    private func dismissBanner() {
        UserDefaults.standard.set(true, forKey: Self.bannerDismissedKey)
        bannerDismissed = true
    }
}

// App-lifetime singleton so a whisper.cpp download (and its progress) survives navigating
// away from the Models page and back.
@MainActor
final class WhisperModelDownloadManager: ObservableObject {
    static let shared = WhisperModelDownloadManager()

    @Published var installedTiers: Set<UInt8> = []
    @Published var missingCoreml: Set<UInt8> = []
    @Published var downloading: UInt8? = nil
    @Published var downloadPhase: DownloadPhase = .ggml
    @Published var progress: Double = 0
    @Published var downloadedMB: Double = 0
    @Published var totalMB: Double = 0

    private var coremlQueue: [UInt8] = []
    private nonisolated var manager: ModelManager { AppController.shared.manager }

    private init() { refreshInstalled() }

    func hasCoreml(_ tierId: UInt8) -> Bool {
        installedTiers.contains(tierId) && !missingCoreml.contains(tierId)
    }

    func refreshInstalled() {
        installedTiers = Set(manager.installedTiers())
        missingCoreml = Set(manager.installedTiersMissingCoreml())
    }

    func downloadModel(_ tier: UInt8) {
        guard downloading == nil else { return }
        downloading = tier
        downloadPhase = .ggml
        progress = 0; downloadedMB = 0; totalMB = 0

        let cb = ProgressHandler { [weak self] info in
            let phase = info.phase, done = info.done
            let downloaded = info.bytesDownloaded, total = info.totalBytes
            Task { @MainActor in self?.applyProgress(phase: phase, downloaded: downloaded, total: total, done: done, onDone: nil) }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do { try self.manager.download(tier: tier, callback: cb) }
            catch { await MainActor.run { self.downloading = nil } }
        }
    }

    func startCoremlMigration() {
        guard downloading == nil else { return }
        coremlQueue = Array(missingCoreml).sorted()
        processCoremlQueue()
    }

    // Per-tier opt-in download of the Neural Engine encoder.
    func enableOptimization(_ tier: UInt8) {
        guard downloading == nil else { return }
        coremlQueue = [tier]
        processCoremlQueue()
    }

    // Removes ONLY the Core ML encoder bundle; the ggml model stays installed.
    func removeOptimization(_ tier: UInt8) {
        try? manager.deleteCoreml(tier: tier)
        refreshInstalled()
        AppController.shared.refresh()
    }

    func deleteModel(_ tier: UInt8) {
        try? manager.delete(tier: tier)
        refreshInstalled()
        AppController.shared.refresh()
    }

    private func processCoremlQueue() {
        guard let tier = coremlQueue.first else { return }
        coremlQueue.removeFirst()

        downloading = tier
        downloadPhase = .coreMl
        progress = 0; downloadedMB = 0; totalMB = 0

        let cb = ProgressHandler { [weak self] info in
            let phase = info.phase, done = info.done
            let downloaded = info.bytesDownloaded, total = info.totalBytes
            Task { @MainActor in self?.applyProgress(phase: phase, downloaded: downloaded, total: total, done: done, onDone: { $0.processCoremlQueue() }) }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do { try self.manager.downloadCoremlOnly(tier: tier, callback: cb) }
            catch { await MainActor.run { self.downloading = nil; self.coremlQueue.removeAll() } }
        }
    }

    private func applyProgress(phase: DownloadPhase, downloaded: UInt64, total: UInt64, done: Bool, onDone: ((WhisperModelDownloadManager) -> Void)?) {
        downloadPhase = phase
        if total > 0 { progress = Double(downloaded) / Double(total) }
        downloadedMB = Double(downloaded) / 1_000_000
        totalMB = Double(total) / 1_000_000
        if done {
            downloading = nil
            refreshInstalled()
            if let onDone { onDone(self) } else { AppController.shared.refresh() }
        }
    }
}

private class ProgressHandler: DownloadProgressCallback {
    let handler: (DownloadProgressInfo) -> Void
    init(_ handler: @escaping (DownloadProgressInfo) -> Void) { self.handler = handler }
    func onProgress(progress: DownloadProgressInfo) { handler(progress) }
}

// App-lifetime singleton so a download keeps running (and its progress is visible)
// even when the user navigates away from the Models page and back.
@MainActor
final class ParakeetDownloadManager: ObservableObject {
    static let shared = ParakeetDownloadManager()

    @Published var installed = ParakeetEngine.isInstalled()
    @Published var downloading = false
    @Published var progress: Double = 0

    private init() {}

    func refreshInstalled() {
        if !downloading { installed = ParakeetEngine.isInstalled() }
    }

    func download() {
        guard !downloading else { return }   // already in flight — don't start a second
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
                self.installed = ParakeetEngine.isInstalled()
            }
        }
    }

    func remove() {
        guard !downloading else { return }
        try? ParakeetEngine.delete()
        installed = false
        AppController.shared.refresh()
    }
}

// Catalog card for the optional Parakeet engine. Download is user-initiated (never auto).
private struct ParakeetCard: View {
    @ObservedObject private var model = ParakeetDownloadManager.shared
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
                Text("The fastest option for English and European languages. Adds punctuation for you.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
        .onAppear { model.refreshInstalled() }
    }
}

// App-lifetime singleton so a WhisperKit download survives navigation away and back.
@MainActor
final class WhisperKitDownloadManager: ObservableObject {
    static let shared = WhisperKitDownloadManager()

    @Published var installed: Set<WhisperKitEngine.Model> = []
    @Published var downloading: WhisperKitEngine.Model? = nil
    @Published var progress: Double = 0

    private init() { refreshInstalled() }

    func refreshInstalled() {
        guard downloading == nil else { return }
        installed = Set(WhisperKitEngine.Model.allCases.filter { WhisperKitEngine.isInstalled($0) })
    }

    func download(_ model: WhisperKitEngine.Model) {
        guard downloading == nil else { return }   // one download at a time
        downloading = model
        progress = 0
        Task {
            do {
                try await WhisperKitEngine.download(model) { p in
                    Task { @MainActor in self.progress = p }
                }
                self.downloading = nil
                self.installed.insert(model)
                AppController.shared.refresh()
            } catch {
                self.downloading = nil
                self.refreshInstalled()
            }
        }
    }

    func remove(_ model: WhisperKitEngine.Model) {
        guard downloading == nil else { return }
        try? WhisperKitEngine.delete(model)
        installed.remove(model)
        AppController.shared.refresh()
    }
}

// Catalog card for WhisperKit with two user-selectable models. Download is user-initiated.
private struct WhisperKitCard: View {
    @ObservedObject private var model = WhisperKitDownloadManager.shared
    @State private var pendingRemoval: WhisperKitEngine.Model? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("WhisperKit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("ANE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
            }

            Text("Fast, private transcription in 90+ languages, powered by Apple's Neural Engine. Pick a size below.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(WhisperKitEngine.Model.allCases, id: \.self) { variant in
                whisperKitRow(variant)
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .alert(
            "Remove WhisperKit model?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Remove", role: .destructive) {
                if let m = pendingRemoval { model.remove(m) }
                pendingRemoval = nil
            }
        } message: {
            Text("Frees disk space. You can re-download it anytime.")
        }
        .onAppear { model.refreshInstalled() }
    }

    @ViewBuilder
    private func whisperKitRow(_ variant: WhisperKitEngine.Model) -> some View {
        let isDownloading = model.downloading == variant
        VStack(spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                    Text("~\(variant.diskSizeMB) MB")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.tertiary)
                        .monospacedDigit()
                }

                Spacer()

                if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(AppTheme.secondary)
                        Text("\(Int(model.progress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                            .monospacedDigit()
                    }
                } else if model.installed.contains(variant) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                            .font(.system(size: 13))
                        Button { pendingRemoval = variant } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("Download") { model.download(variant) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.divider)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(model.downloading != nil)
                        .opacity(model.downloading != nil ? 0.4 : 1)
                }
            }

            if isDownloading {
                ProgressView(value: model.progress).tint(AppTheme.accent)
            }
        }
    }
}

// App-lifetime singleton so an EOU download survives navigation away and back.
@MainActor
final class EouDownloadManager: ObservableObject {
    static let shared = EouDownloadManager()

    @Published var installed = EouStreamingEngine.isInstalled()
    @Published var downloading = false
    @Published var progress: Double = 0

    private init() {}

    func refreshInstalled() {
        if !downloading { installed = EouStreamingEngine.isInstalled() }
    }

    func download() {
        guard !downloading else { return }
        downloading = true
        progress = 0
        Task {
            do {
                try await EouStreamingEngine.download { p in
                    Task { @MainActor in self.progress = p }
                }
                self.downloading = false
                self.installed = true
                AppController.shared.refresh()
            } catch {
                self.downloading = false
                self.installed = EouStreamingEngine.isInstalled()
            }
        }
    }

    func remove() {
        guard !downloading else { return }
        try? EouStreamingEngine.delete()
        installed = false
        AppController.shared.refresh()
    }
}

// Catalog card for the EOU 120M low-latency streaming model.
private struct EouCard: View {
    @ObservedObject private var model = EouDownloadManager.shared
    @State private var pendingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("Parakeet Realtime")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text("Live typing")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text("~120 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("Enables live typing as you speak. Required for the streaming toggle in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
        .alert("Remove Parakeet Realtime model?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            Text("Frees ~120 MB. Live typing will be disabled until you re-download it.")
        }
        .onAppear { model.refreshInstalled() }
    }
}
