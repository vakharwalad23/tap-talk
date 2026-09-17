import SwiftUI

// Single source of truth for user-facing Orukeet claims, normalized from WER/CER into
// plain language. The speed clause is gated on an on-device measurement (see the latency
// gate task); until that flips true, no speed claim is shown, per performance.md.
enum OrukeetCopy {
    // Set true only after the key-up-to-paste median-of-10 confirms parity with Parakeet
    // on target hardware (oldest and newest Apple Silicon available).
    static let speedParityVerified = false

    static var badge: String { speedParityVerified ? "More accurate, same speed" : "More accurate" }
    static var cardSubtitle: String {
        speedParityVerified
            ? "Makes fewer mistakes than Parakeet, at the same speed."
            : "Makes fewer mistakes than Parakeet."
    }
    static var bannerHeadline: String {
        speedParityVerified
            ? "Orukeet is here - more accurate, same speed."
            : "Orukeet is here - more accurate transcription."
    }
    // Honest, sourced tooltip. FLEURS pooled WER 13.98 to 11.80 = about 15 percent fewer
    // word errors across 25 languages (our int8 benchmark). No jargon in the surface text.
    static let tooltip =
        "Independently benchmarked to make about 15 percent fewer word mistakes than Parakeet across 25 languages."
}

// Small, unobtrusive accuracy tag shown next to the Orukeet name.
struct AccuracyBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .bold))
            Text(OrukeetCopy.badge).font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(AppTheme.success)
        .foregroundStyle(.white)
        .clipShape(Capsule())
        .help(OrukeetCopy.tooltip)
    }
}

// App-lifetime singleton so download+compile keep running (and stay visible) when the
// user navigates away from Models and back. Orukeet is the only engine with an on-device
// compile phase, so the status enum has an explicit .compiling state.
@MainActor
final class OrukeetInstaller: ObservableObject {
    static let shared = OrukeetInstaller()

    enum Status: Equatable {
        case idle
        case downloading(Double)
        case compiling
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status
    private var task: Task<Void, Never>?

    private init() { status = OrukeetEngine.isInstalled() ? .ready : .idle }

    func refresh() {
        switch status {
        case .idle, .ready: status = OrukeetEngine.isInstalled() ? .ready : .idle
        default: break
        }
    }

    var busy: Bool {
        switch status { case .downloading, .compiling: return true; default: return false }
    }

    func install() {
        if busy { return }
        if OrukeetEngine.isInstalled() {
            status = .ready
            OrukeetMigration.shared.completeIfEligible()
            return
        }
        status = .downloading(0)
        task?.cancel()
        task = Task { await run() }
    }

    private func run() async {
        do {
            if !OrukeetEngine.isDownloaded() {
                try await OrukeetEngine.download { p in
                    Task { @MainActor in
                        // Unstructured Tasks can deliver out of order; never show progress going backward.
                        if case .downloading(let current) = self.status, p < current { return }
                        self.status = .downloading(p)
                    }
                }
            }
            status = .compiling
            try await Task.detached(priority: .userInitiated) { try OrukeetEngine.compile() }.value
            status = .ready
            OrukeetMigration.shared.completeIfEligible()
            AppController.shared.adoptDownloadedEngine(.orukeet)
        } catch is CancellationError {
            status = OrukeetEngine.isInstalled() ? .ready : .idle
        } catch let error as URLError where error.code == .cancelled {
            status = OrukeetEngine.isInstalled() ? .ready : .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func retry() { install() }

    func remove() {
        task?.cancel()
        task = nil
        try? OrukeetEngine.delete()
        status = .idle
        AppController.shared.handleEngineRemoved(.orukeet)
    }
}

// Catalog card for the Orukeet engine. Download is user-initiated (never auto).
struct OrukeetCard: View {
    @ObservedObject private var model = OrukeetInstaller.shared
    @State private var pendingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Text(LocalEngine.orukeet.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                AccuracyBadge()
                Spacer()
                Text("~467 MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center) {
                Text("Orukeet r3. \(OrukeetCopy.cardSubtitle) English and 24 European languages.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                statusControl
            }

            if case .downloading(let p) = model.status {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: p).tint(AppTheme.accent)
                    Text("\(Int(p * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                        .monospacedDigit()
                }
            }

            if case .failed(let message) = model.status {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        .alert("Remove \(LocalEngine.orukeet.displayName)?", isPresented: $pendingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { model.remove() }
        } message: {
            Text("Frees ~467 MB and switches back to Parakeet. You can re-download it anytime.")
        }
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private var statusControl: some View {
        switch model.status {
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(AppTheme.secondary)
                Text("Downloading").font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
            }
        case .compiling:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(AppTheme.secondary)
                Text("Preparing").font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
            }
        case .ready:
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.success).font(.system(size: 13))
                    Text("Installed").font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.success)
                }
                Button { pendingRemoval = true } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.plain)
            }
        case .failed:
            Button("Retry") { model.retry() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(AppTheme.divider)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .idle:
            Button("Download") { model.install() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(AppTheme.divider)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
