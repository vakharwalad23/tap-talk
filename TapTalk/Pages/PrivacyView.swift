import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppTheme.primary)
                    Text("What TapTalk does - and doesn't - do with your data")
                        .font(.caption)
                        .foregroundStyle(AppTheme.tertiary)
                }
                .padding(.bottom, 20)

                privacySection("Data collected", body: "None. TapTalk does not collect, store, or transmit any personal data, usage metrics, or crash reports.")

                privacySection("Microphone", body: "Audio is recorded directly from your microphone and processed immediately. No audio files are saved to disk. The recording is discarded after transcription.")

                privacySection("Local transcription", body: "When using the Local engine, transcription runs entirely on your device using models stored in Application Support. Your audio never leaves your Mac.")

                privacySection("Cloud transcription", body: "When using the Cloud engine, audio is sent to OpenAI's Whisper API over HTTPS using your API key. OpenAI's data retention and usage policies apply. Your API key is stored in the macOS Keychain - never in plain text or UserDefaults.")

                privacySection("Clipboard", body: "TapTalk briefly writes transcribed text to the clipboard to paste it into the focused app, then restores the previous clipboard contents. No clipboard data is retained beyond this operation.")

                privacySection("Telemetry", body: "None. No analytics, no crash reporting, no network requests beyond cloud transcription when you explicitly enable it.")
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
    }

    private func privacySection(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
    }
}
