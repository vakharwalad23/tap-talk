import SwiftUI

struct RecordView: View {
    // ctrl for actions and published state (AppController @Published properties)
    @ObservedObject private var ctrl     = AppController.shared
    // state observed directly — nested ObservableObject changes don't bubble up through ctrl
    @ObservedObject private var state    = AppController.shared.state
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                modelControl
                languageControl
                Spacer()
            }
            .disabled(state.recording || state.loadingModel || state.transcribing || state.rewriting)
            .padding(.bottom, 20)

            Waveform(isRecording: state.recording)
                .padding(.bottom, 8)

            Text(state.status)
                .font(.system(size: 12))
                .foregroundStyle(state.recording ? AppTheme.danger : AppTheme.secondary)
                .frame(height: 18)
                .padding(.bottom, 16)

            if state.streamingActive {
                streamingPreview
                    .padding(.bottom, 16)
            } else if !state.transcriptText.isEmpty {
                TranscriptDisplay(
                    text: state.transcriptText,
                    language: state.transcriptLang,
                    durationMs: state.transcriptMs,
                    audioDuration: state.audioDuration
                )
                .padding(.bottom, 16)
            }

            Spacer()

            Button(action: ctrl.toggleRecording) {
                HStack(spacing: 8) {
                    Image(systemName: state.recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(state.recording ? "Stop Recording" : "Record")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    state.recording
                        ? AppTheme.danger
                        : (state.canRecord ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!state.canRecord && !state.recording)

            Button("") { ctrl.cancelRecording() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .hidden()

            HStack(spacing: 5) {
                Image(systemName: state.hotkeyActive ? "keyboard.fill" : "keyboard")
                    .font(.system(size: 10))
                Text(state.hotkeyActive
                     ? "Hotkey active · \(keyLabel)"
                     : "\(keyLabel) push-to-talk")
                    .font(.system(size: 11))
            }
            .foregroundStyle(state.hotkeyActive ? AppTheme.success : AppTheme.tertiary)
            .padding(.top, 10)
        }
        .padding(24)
        .background(AppTheme.windowBg)
        // Re-register on window open to pick up any hotkey code change from settings
        .onAppear { ctrl.setupHotkey() }
    }

    private var keyLabel: String { AppTheme.keyLabel(for: settings.hotkeyCode) }

    // Left control: a static chip naming the active engine.
    @ViewBuilder
    private var modelControl: some View {
        if settings.transcriptionEngine == .local {
            switch settings.localEngine {
            case .parakeet:
                engineChip(LocalEngine.parakeet.displayName, icon: "bolt.fill")
            case .nemotron:
                engineChip(LocalEngine.nemotron.displayName, icon: "globe")
            }
        } else {
            engineChip("Cloud · \(settings.cloudModel)", icon: "cloud")
        }
    }

    // Right control: a language picker only when the active engine supports selecting one.
    @ViewBuilder
    private var languageControl: some View {
        if settings.transcriptionEngine == .local && !settings.localEngine.supportsLanguageSelection {
            autoLangChip(settings.localEngine.autoLanguageLabel)
        } else if settings.transcriptionEngine == .local {
            LanguagePicker(
                selectedLanguage: $settings.selectedLanguage,
                languages: settings.localEngine.supportedLanguages
            )
        } else {
            LanguagePicker(
                selectedLanguage: $settings.selectedLanguage,
                languages: LanguagePicker.cloudLanguages
            )
        }
    }

    private func engineChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // maxWidth (not fixed) so the row can shrink instead of overflowing a narrow window.
        .frame(maxWidth: 200, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    // Live transcript while streaming: confirmed text in normal weight, volatile tail dimmed.
    private var streamingPreview: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(state.streamingConfirmed)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.primary)
            Text(state.streamingVolatile)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.tertiary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.sectionBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: 1))
    }

    // Shown instead of the language picker for auto-only engines (e.g. Parakeet).
    private func autoLangChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe").font(.system(size: 10))
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 140, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}
