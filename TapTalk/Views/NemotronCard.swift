import SwiftUI

// App-lifetime singleton so a download keeps running (and its progress is visible)
// even when the user navigates away from the Models page and back.
@MainActor
final class NemotronDownloadManager: ObservableObject {
    static let shared = NemotronDownloadManager()

    @Published var installed = NemotronEngine.isInstalled()
    @Published var downloading = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?

    private init() {}

    func refreshInstalled() {
        if !downloading { installed = NemotronEngine.isInstalled() }
    }

    func download() {
        guard !downloading else { return }   // already in flight - don't start a second
        downloading = true
        progress = 0
        errorMessage = nil
        Task {
            do {
                try await NemotronEngine.download { p in
                    Task { @MainActor in self.progress = p }
                }
                self.downloading = false
                self.installed = true
                AppController.shared.adoptDownloadedEngine(.nemotron)
            } catch {
                self.downloading = false
                self.installed = NemotronEngine.isInstalled()
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func remove() {
        guard !downloading else { return }
        try? NemotronEngine.delete()
        installed = false
        // Fall back to the highest-priority installed engine so the app is never left on an
        // engine whose model was just deleted.
        AppController.shared.handleEngineRemoved(.nemotron)
    }
}

// Catalog card for the multilingual engine. Download is user-initiated (never auto).
struct NemotronCard: View {
    @ObservedObject private var model = NemotronDownloadManager.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var pendingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text(LocalEngine.nemotron.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Text("~640 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("NVIDIA Nemotron 3.5 ASR. Covers Hindi and the languages Parakeet doesn't - pick yours in the Record tab.")
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
                        UseEngineControl(isInUse: settings.isInUse(.nemotron)) { settings.use(.nemotron) }
                        Button { pendingRemoval = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(model.errorMessage == nil ? "Download" : "Retry") { model.download() }
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

            if !model.downloading, !model.installed, let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Only Nemotron produces Devanagari, so the choice belongs to its card.
            if settings.isInUse(.nemotron) {
                Divider().background(AppTheme.divider)
                hindiScriptPicker
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.divider, lineWidth: 1)
        )
        .alert("Remove \(LocalEngine.nemotron.displayName)?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            Text("Frees ~640 MB and switches back to Parakeet. You can re-download it anytime.")
        }
        .onAppear { model.refreshInstalled() }
    }

    private var hindiScriptPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hindi script")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
            HStack(spacing: 8) {
                ForEach(HindiScript.allCases, id: \.self) { script in
                    scriptButton(script)
                }
            }
            Text(scriptHint)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Roman script needs Hindi selected and Smart Mode; say which is missing rather than leaving a
    // control that quietly does nothing.
    private var scriptHint: String {
        guard settings.hindiScript == .roman else {
            return "Devanagari is what the model produces. Roman writes it the way people type in chat."
        }
        if settings.selectedLanguage != AppContextService.hindiLanguageCode {
            return "Roman applies to Hindi only - pick Hindi in the Record tab. Other languages are pasted as the model produces them."
        }
        return "Roman writes Hindi the way people type it in chat: main kal aaunga. Produced by the rewrite model, so it needs Smart Mode."
    }

    private func scriptButton(_ script: HindiScript) -> some View {
        let active = settings.hindiScript == script
        return Button(action: { settings.hindiScript = script }) {
            Text(script.label)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(active ? AppTheme.accent : AppTheme.windowBg)
                .foregroundStyle(active ? AppTheme.windowBg : AppTheme.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: active ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}
