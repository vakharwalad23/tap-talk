import SwiftUI

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
        guard !downloading else { return }   // already in flight - don't start a second
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
        // Live typing requires Parakeet + EOU together - remove the add-on with the engine
        // so the user isn't left with an orphan model and a stale streaming toggle.
        if EouDownloadManager.shared.installed {
            // EouDownloadManager.remove() already calls AppController.refresh() - let it
            // cover both removals so the controller isn't refreshed twice.
            EouDownloadManager.shared.remove()
        } else {
            SettingsStore.shared.streamingEnabled = false
            AppController.shared.refresh()
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
        // Persisted toggle must match reality so a future re-download doesn't silently
        // re-enable streaming.
        SettingsStore.shared.streamingEnabled = false
        AppController.shared.refresh()
    }
}

// Catalog card for the Parakeet engine. Download is user-initiated (never auto).
// The Live typing add-on (EOU) is nested as a sub-row inside this card so the dependency
// between Parakeet (engine) and EOU (streaming model) is visible in one place.
struct ParakeetCard: View {
    @ObservedObject private var model = ParakeetDownloadManager.shared
    @ObservedObject private var eou = EouDownloadManager.shared
    @State private var pendingRemoval = false
    @State private var pendingEouRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text(LocalEngine.parakeet.displayName)
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
                Text("NVIDIA Parakeet TDT 0.6B v3. The fastest option for English and European languages. Adds punctuation for you.")
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

            // EOU sub-row: only relevant once Parakeet itself is installed.
            if model.installed {
                Divider().background(AppTheme.divider)
                eouSubRow
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .alert("Remove \(LocalEngine.parakeet.displayName)?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            if eou.installed {
                Text("Frees ~930 MB. The Live typing add-on (~440 MB) is removed with it - live streaming will be disabled.")
            } else {
                Text("Frees ~490 MB. You can re-download it anytime.")
            }
        }
        .alert("Remove Live typing add-on?", isPresented: $pendingEouRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { eou.remove() }
        } message: {
            Text("Frees ~440 MB. Live streaming dictation will be disabled until you re-download.")
        }
        .onAppear {
            model.refreshInstalled()
            eou.refreshInstalled()
        }
    }

    private var eouSubRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("Live typing add-on")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                        Text("~440 MB")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                            .monospacedDigit()
                    }
                    Text("Streams words live as you speak. Required for the Live typing toggle in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if eou.downloading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(AppTheme.secondary)
                        Text("\(Int(eou.progress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                            .monospacedDigit()
                    }
                } else if eou.installed {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                            .font(.system(size: 13))
                        Button { pendingEouRemoval = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button("Download") { eou.download() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.divider)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            if eou.downloading {
                ProgressView(value: eou.progress).tint(AppTheme.accent)
            }
        }
    }
}
