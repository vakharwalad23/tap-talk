import SwiftUI

/// The first-run requirements, each read from live state by the Record page.
struct SetupChecklist {
    let speech: Bool
    let microphone: Bool
    let accessibility: Bool

    var isComplete: Bool { speech && microphone && accessibility }
}

/// Session-only memory that the card was shown, so the ready line follows a setup and never greets
/// a returning user. Never persisted, and never read as "setup done": the rows read real state.
@MainActor
final class SetupSession: ObservableObject {
    static let shared = SetupSession()
    @Published var sawIncomplete = false
    @Published var readyDismissed = false
    private init() {}
}

/// Speech model, Microphone and Accessibility on one card, each with the one action that completes it.
struct SetupCard: View {
    let checklist: SetupChecklist

    @ObservedObject private var state = AppController.shared.state
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var permissions = PermissionService.shared
    @ObservedObject private var orukeet = OrukeetInstaller.shared
    @ObservedObject private var nemotron = NemotronDownloadManager.shared
    @ObservedObject private var session = SetupSession.shared
    @State private var tryText = ""

    var body: some View {
        if checklist.isComplete {
            readyLine
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up TapTalk")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.primary)

            VStack(alignment: .leading, spacing: 6) {
                SetupRow(icon: "waveform", title: "Speech model",
                         subtitle: speechSubtitle,
                         done: checklist.speech) { speechControl }
                if !checklist.speech { speechDetail.padding(.leading, 30) }
            }
            SetupRow(icon: "mic", title: "Microphone",
                     subtitle: microphoneSubtitle,
                     done: checklist.microphone) { microphoneControl }
            SetupRow(icon: "keyboard", title: "Accessibility",
                     subtitle: accessibilitySubtitle,
                     done: checklist.accessibility) { accessibilityControl }
            // Asked here, but optional: it never holds the card open.
            if settings.updateCheckConsent == .notAsked {
                Divider()
                UpdateConsentRow()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.divider, lineWidth: 1))
        .onAppear { session.sawIncomplete = true }
    }

    private var readyLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.success)
                Text("Ready - hold \(AppTheme.keyLabel(for: settings.hotkeyCode)) and speak")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Spacer(minLength: 8)
                Button { session.readyDismissed = true } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(AppTheme.tertiary)
                }
                .buttonStyle(.plain)
            }
            TextField("Try it here", text: $tryText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.success.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.success.opacity(0.3), lineWidth: 1))
    }

    private var speechSubtitle: String {
        guard checklist.speech else {
            return "\(LocalEngine.orukeet.displayName) - \(LocalEngine.orukeet.languageSummary)"
        }
        if settings.transcriptionEngine == .cloud { return "Cloud - \(settings.cloudModel)" }
        return "\(settings.localEngine.displayName) - \(settings.localEngine.languageSummary)"
    }

    @ViewBuilder
    private var speechControl: some View {
        if nemotron.downloading {
            spinner("Downloading")
        } else {
            switch orukeet.status {
            case .downloading:
                spinner("Downloading")
            case .compiling:
                spinner("Preparing (one time)")
            case .failed:
                CardButton(title: "Retry", prominent: false) { orukeet.retry() }
            case .ready:
                CardButton(title: "Use Orukeet", prominent: true) {
                    AppController.shared.adoptDownloadedEngine(.orukeet)
                }
            case .idle:
                CardButton(title: "Download (467 MB)", prominent: true) { orukeet.install() }
            }
        }
    }

    // Progress, failure and the other-languages link sit under the speech row; the link is hidden
    // while either download runs so two models never download at once from here.
    @ViewBuilder
    private var speechDetail: some View {
        if nemotron.downloading {
            progress(nemotron.progress, label: "Downloading \(LocalEngine.nemotron.displayName)")
        } else {
            switch orukeet.status {
            case .downloading(let p):
                progress(p, label: "Downloading \(LocalEngine.orukeet.displayName)")
            case .failed(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                otherLanguagesLink
            case .idle:
                otherLanguagesLink
            case .compiling, .ready:
                EmptyView()
            }
        }
    }

    private var otherLanguagesLink: some View {
        Button("Other languages (Hindi + 100 more)") { nemotron.download() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .underline()
            .foregroundStyle(AppTheme.secondary)
    }

    private func progress(_ value: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: value).tint(AppTheme.accent)
        }
    }

    private var microphoneSubtitle: String {
        permissions.microphone == .denied
            ? "Turned off for TapTalk in System Settings"
            : "Hears you only while you hold the hotkey"
    }

    @ViewBuilder
    private var microphoneControl: some View {
        switch permissions.microphone {
        case .notDetermined:
            CardButton(title: "Allow", prominent: true) { permissions.requestMicrophone() }
        case .denied:
            CardButton(title: "Open Settings", prominent: false) { permissions.openMicrophoneSettings() }
        case .granted:
            EmptyView()
        }
    }

    private var accessibilitySubtitle: String {
        state.hotkeyNeedsRestart
            ? "Allowed - TapTalk needs a restart to use it"
            : "Detects the hotkey and pastes the text"
    }

    @ViewBuilder
    private var accessibilityControl: some View {
        if state.hotkeyNeedsRestart && (orukeet.busy || nemotron.downloading) {
            // A relaunch would throw away the download in flight.
            Text("Restart after the download")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondary)
        } else if state.hotkeyNeedsRestart {
            CardButton(title: "Restart TapTalk", prominent: true) { permissions.restartApp() }
        } else if permissions.isRepairingAccessibility {
            spinner("Opening")
        } else {
            CardButton(title: "Allow", prominent: true) { permissions.repairAccessibility() }
        }
    }

    private func spinner(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small).tint(AppTheme.secondary)
            Text(label).font(.system(size: 11)).foregroundStyle(AppTheme.secondary)
        }
    }
}

private struct SetupRow<Control: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let done: Bool
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(done ? AppTheme.success : AppTheme.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.success)
            } else {
                control
            }
        }
    }
}

struct CardButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : AppTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(prominent ? AppTheme.accent : AppTheme.divider)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
