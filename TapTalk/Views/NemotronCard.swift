import SwiftUI

// App-lifetime singleton so a download keeps running (and its progress is visible)
// even when the user navigates away from the Models page and back.
@MainActor
final class NemotronDownloadManager: ObservableObject {
    static let shared = NemotronDownloadManager()

    @Published var installed = NemotronEngine.isInstalled()
    @Published var downloading = false
    @Published var progress: Double = 0

    private init() {}

    func refreshInstalled() {
        if !downloading { installed = NemotronEngine.isInstalled() }
    }

    func download() {
        guard !downloading else { return }   // already in flight — don't start a second
        downloading = true
        progress = 0
        Task {
            do {
                try await NemotronEngine.download { p in
                    Task { @MainActor in self.progress = p }
                }
                self.downloading = false
                self.installed = true
                AppController.shared.refresh()
            } catch {
                self.downloading = false
                self.installed = NemotronEngine.isInstalled()
            }
        }
    }

    func remove() {
        guard !downloading else { return }
        try? NemotronEngine.delete()
        installed = false
        // Falling back to Parakeet keeps the app in a working state rather than sitting on
        // an engine whose model was just deleted.
        if SettingsStore.shared.localEngine == .nemotron {
            SettingsStore.shared.localEngine = .parakeet
        }
        AppController.shared.refresh()
    }
}

// Catalog card for the multilingual engine. Download is user-initiated (never auto).
struct NemotronCard: View {
    @ObservedObject private var model = NemotronDownloadManager.shared
    @State private var pendingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text("Multilingual")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Text("~640 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("For Hindi and other languages Parakeet doesn't cover. Pick your language in the Record tab.")
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
        .alert("Remove Multilingual model?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            Text("Frees ~640 MB and switches back to Parakeet. You can re-download it anytime.")
        }
        .onAppear { model.refreshInstalled() }
    }
}
