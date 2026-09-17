import SwiftUI

// Shared navigation so a banner on the Record page can route the user to Models.
@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()
    @Published var selection: NavItem = .record
    private init() {}
}

// One-time, non-destructive Orukeet migration. Removes the old Parakeet model only for
// users who do not depend on it for live typing, and only after Orukeet is installed and
// compiled successfully.
@MainActor
final class OrukeetMigration: ObservableObject {
    static let shared = OrukeetMigration()
    @Published private(set) var showBanner = false
    private let settings = SettingsStore.shared
    private init() {}

    // Called once from AppController.setup() (on the main thread). Resolves the migration
    // state exactly once. orukeetMigrationState is a brand-new key, so .unevaluated IS the
    // first-launch signal for existing and new users alike; they are told apart by what is
    // installed (a new user has nothing installed), not by a separate launch flag - a fresh
    // launch flag reads false for everyone the first time and the banner would never fire.
    func evaluate() {
        if settings.orukeetMigrationState == .unevaluated {
            if eligible() {
                settings.orukeetMigrationState = .pending
            } else {
                settings.orukeetMigrationState = .notApplicable
                // Brand-new user (nothing installed at all): default to Orukeet.
                if !ParakeetEngine.isInstalled(),
                   !NemotronEngine.isInstalled(),
                   !OrukeetEngine.isInstalled() {
                    settings.localEngine = .orukeet
                }
            }
        }

        // Recompile a stale/interrupted cache (e.g. after a macOS upgrade) without re-download.
        Task.detached { OrukeetEngine.reconcileCompiledCache() }

        // Self-heal: if a prior upgrade's compile finished out-of-band, finish the switch
        // instead of showing a banner whose Upgrade button would no-op.
        if settings.orukeetMigrationState == .pending, OrukeetEngine.isInstalled() {
            completeIfEligible()
        }

        showBanner = (settings.orukeetMigrationState == .pending)
    }

    private func eligible() -> Bool {
        settings.transcriptionEngine == .local
            && settings.localEngine == .parakeet
            && ParakeetEngine.isInstalled()
            && !EouStreamingEngine.isInstalled()   // live-typing users keep Parakeet, not switched
            && !OrukeetEngine.isInstalled()
    }

    func startUpgrade() {
        AppNavigation.shared.selection = .models
        OrukeetInstaller.shared.install()
    }

    func dismiss() {
        settings.orukeetMigrationState = .dismissed
        showBanner = false
    }

    // Called by OrukeetInstaller when Orukeet becomes installed+compiled.
    func completeIfEligible() {
        guard OrukeetEngine.isInstalled() else { return }
        switch settings.orukeetMigrationState {
        case .pending, .dismissed:
            // Existing (non-live-typing) user upgraded: switch the active engine to Orukeet.
            // Parakeet is kept installed as a fallback - nothing is deleted.
            settings.localEngine = .orukeet
            settings.orukeetMigrationState = .done
            showBanner = false
            AppController.shared.refresh()
        case .notApplicable, .done, .unevaluated:
            // New user, live-typing user, or already switched: leave the setup intact.
            break
        }
    }
}

// Dismissible upgrade bar shown on the Record page for pending migrations.
struct MigrationBanner: View {
    @ObservedObject private var migration = OrukeetMigration.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(AppTheme.accent)
            Text(OrukeetCopy.bannerHeadline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Upgrade") { migration.startUpgrade() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button { migration.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(AppTheme.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent.opacity(0.25), lineWidth: 1))
    }
}
