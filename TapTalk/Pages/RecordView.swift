import SwiftUI
import Carbon.HIToolbox

struct RecordView: View {
    @ObservedObject private var ctrl     = AppController.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ModelTierPicker(selectedTier: $settings.selectedTier, installedTiers: ctrl.installedTiers)
                LanguagePicker(selectedLanguage: $settings.selectedLanguage)
                Spacer()
            }
            .disabled(ctrl.state.recording || ctrl.state.loadingModel || ctrl.state.transcribing)
            .padding(.bottom, 20)

            Waveform(isRecording: ctrl.state.recording)
                .padding(.bottom, 8)

            Text(ctrl.state.status)
                .font(.system(size: 12))
                .foregroundStyle(ctrl.state.recording ? AppTheme.danger : AppTheme.secondary)
                .frame(height: 18)
                .padding(.bottom, 16)

            if !ctrl.state.transcriptText.isEmpty {
                TranscriptDisplay(
                    text: ctrl.state.transcriptText,
                    language: ctrl.state.transcriptLang,
                    durationMs: ctrl.state.transcriptMs,
                    audioDuration: ctrl.state.audioDuration
                )
                .padding(.bottom, 16)
            }

            Spacer()

            Button(action: ctrl.toggleRecording) {
                HStack(spacing: 8) {
                    Image(systemName: ctrl.state.recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(ctrl.state.recording ? "Stop Recording" : "Record")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    ctrl.state.recording
                        ? AppTheme.danger
                        : (ctrl.state.canRecord ? AppTheme.accent : AppTheme.accent.opacity(0.4))
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!ctrl.state.canRecord && !ctrl.state.recording)

            Button("") { ctrl.cancelRecording() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0)
                .hidden()

            HStack(spacing: 5) {
                Image(systemName: ctrl.state.hotkeyActive ? "keyboard.fill" : "keyboard")
                    .font(.system(size: 10))
                Text(ctrl.state.hotkeyActive
                     ? "Hotkey active · \(keyLabel)"
                     : "\(keyLabel) push-to-talk")
                    .font(.system(size: 11))
            }
            .foregroundStyle(ctrl.state.hotkeyActive ? AppTheme.success : AppTheme.tertiary)
            .padding(.top, 10)
        }
        .padding(24)
        .background(AppTheme.windowBg)
        // Re-register hotkey when window opens (picks up any key code change from settings)
        .onAppear { ctrl.setupHotkey() }
        .onChange(of: settings.selectedTier)          { _ in ctrl.loadSelectedTier() }
        .onChange(of: settings.transcriptionEngine)   { _ in ctrl.loadSelectedTier() }
    }

    private var keyLabel: String {
        switch Int(settings.hotkeyCode) {
        case kVK_RightCommand: return "Right ⌘"
        case kVK_RightOption:  return "Right ⌥"
        case kVK_RightControl: return "Right ⌃"
        case kVK_RightShift:   return "Right ⇧"
        case kVK_Command:      return "Left ⌘"
        case kVK_Option:       return "Left ⌥"
        case kVK_Control:      return "Left ⌃"
        case kVK_Shift:        return "Left ⇧"
        default:               return "Key \(settings.hotkeyCode)"
        }
    }
}
