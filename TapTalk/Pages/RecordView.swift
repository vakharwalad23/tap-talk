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
        // selectedTier has no Combine sink, so reload here; engine/model changes are handled
        // centrally by AppController's sinks (avoids a duplicate, racing reload).
        .onChange(of: settings.selectedTier) { _ in ctrl.loadSelectedTier() }
    }

    private var keyLabel: String { AppTheme.keyLabel(for: settings.hotkeyCode) }

    // Left control: a tier picker for whisper.cpp, a static chip for the other engines.
    @ViewBuilder
    private var modelControl: some View {
        if settings.transcriptionEngine == .local {
            switch settings.localEngine {
            case .whisper:
                ModelTierPicker(selectedTier: $settings.selectedTier, installedTiers: ctrl.installedTiers)
            case .parakeet:
                engineChip("Parakeet", icon: "bolt.fill")
            case .whisperKit:
                engineChip("WhisperKit · \(settings.whisperKitModel.displayName)", icon: "waveform")
            case .appleSpeech:
                engineChip("Apple Speech", icon: "apple.logo")
            }
        } else {
            ModelTierPicker(selectedTier: $settings.selectedTier, installedTiers: ctrl.installedTiers)
        }
    }

    // Right control: a language picker only when the active engine supports selecting one.
    @ViewBuilder
    private var languageControl: some View {
        if settings.transcriptionEngine == .local && !settings.localEngine.supportsLanguageSelection {
            autoLangChip(settings.localEngine.autoLanguageLabel)
        } else {
            LanguagePicker(selectedLanguage: $settings.selectedLanguage)
        }
    }

    private func engineChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 200, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }

    // Shown instead of the language picker for auto-only engines (e.g. Parakeet).
    private func autoLangChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "globe").font(.system(size: 10))
            Text(label).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 140, alignment: .leading)
        .background(AppTheme.sectionBg)
        .foregroundStyle(AppTheme.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(AppTheme.divider, lineWidth: 1)
        )
    }
}
