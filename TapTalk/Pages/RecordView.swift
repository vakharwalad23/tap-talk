import SwiftUI

struct RecordView: View {
    // ctrl for actions and installedTiers (AppController @Published properties)
    @ObservedObject private var ctrl     = AppController.shared
    // state observed directly — nested ObservableObject changes don't bubble up through ctrl
    @ObservedObject private var state    = AppController.shared.state
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if settings.transcriptionEngine == .local && settings.localEngine == .parakeet {
                    parakeetChip
                    parakeetLangChip
                } else {
                    ModelTierPicker(selectedTier: $settings.selectedTier, installedTiers: ctrl.installedTiers)
                    LanguagePicker(selectedLanguage: $settings.selectedLanguage)
                }
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

            if !state.transcriptText.isEmpty {
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
        .onChange(of: settings.selectedTier)        { _ in ctrl.loadSelectedTier() }
        .onChange(of: settings.transcriptionEngine) { _ in ctrl.loadSelectedTier() }
    }

    private var keyLabel: String { AppTheme.keyLabel(for: settings.hotkeyCode) }

    private var parakeetChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill").font(.system(size: 10))
            Text("Parakeet").font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 160, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    // Parakeet auto-detects across ~25 European languages — no manual language choice.
    private var parakeetLangChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe").font(.system(size: 10))
            Text("Auto · EU").font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 160, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}
