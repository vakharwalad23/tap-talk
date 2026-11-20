import SwiftUI
import TapTalkUpdates

/// The one-time question that turns the daily update check on or off.
struct UpdateConsentRow: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Check for updates once a day?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text("Asks GitHub for the latest version only")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
            }
            Spacer(minLength: 8)
            CardButton(title: "No", prominent: false) { settings.updateCheckConsent = .off }
            CardButton(title: "Yes", prominent: true) { settings.updateCheckConsent = .on }
        }
    }
}

/// A newer release, with the exact next step for how this copy was installed.
struct UpdateBanner: View {
    let notice: UpdateNotice
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.accent)
                Text("TapTalk \(notice.version) is available")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Spacer(minLength: 8)
                if case .open = notice.action {
                    CardButton(title: "Download", prominent: true) { UpdateService.shared.perform(notice.action) }
                }
                Button { UpdateService.shared.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(AppTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
            if case .copyCommand(let command) = notice.action {
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.primary)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    CardButton(title: copied ? "Copied" : "Copy", prominent: false) {
                        UpdateService.shared.perform(notice.action)
                        copied = true
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.windowBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .bannerStyle()
    }
}

extension View {
    /// The Record page's dismissible bar look, shared with the Orukeet migration banner.
    func bannerStyle() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent.opacity(0.25), lineWidth: 1))
    }
}
