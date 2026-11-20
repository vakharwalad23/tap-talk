import SwiftUI

/// The update-check switch and what TapTalk does and doesn't do with your data, last on Settings.
struct PrivacySettingsSection: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        SettingsSection("Privacy") {
            SettingRow("Check for updates once a day") {
                Toggle("", isOn: Binding(
                    get: { settings.updateCheckConsent == .on },
                    set: { settings.updateCheckConsent = $0 ? .on : .off }
                ))
                .labelsHidden()
            }
            Divider().background(AppTheme.divider)

            statement("Data collected", body: "None. TapTalk does not collect, store, or transmit any personal data, usage metrics, or crash reports.")

            statement("Microphone", body: "Audio is recorded directly from your microphone and processed immediately. No audio files are saved to disk. The recording is discarded after transcription.")

            statement("Local transcription", body: "When using the Local engine, transcription runs entirely on your device using models stored in Application Support. Your audio never leaves your Mac.")

            statement("Cloud transcription", body: "When using the Cloud engine, audio is sent to OpenAI's Whisper API over HTTPS using your API key. OpenAI's data retention and usage policies apply. Your API key is stored in the macOS Keychain - never in plain text or UserDefaults.")

            statement("Clipboard", body: "TapTalk briefly writes transcribed text to the clipboard to paste it into the focused app, then restores the previous clipboard contents. No clipboard data is retained beyond this operation.")

            statement("Learning from corrections", body: "After TapTalk pastes, it reads that text field once, on your next dictation, to see whether you fixed a word it typed. Only the fixed words are kept, on this Mac. Password fields are never read. Turn it off on the Words page.")

            statement("Update checks", body: "Off until you say yes. When on, TapTalk asks GitHub once a day for the latest release version. Nothing about you or your Mac is sent beyond what any web request carries.")

            statement("Telemetry", body: "None. No analytics, no crash reporting, and no network requests unless you turn on cloud transcription or update checks.")
        }
    }

    private func statement(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Text(body)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
