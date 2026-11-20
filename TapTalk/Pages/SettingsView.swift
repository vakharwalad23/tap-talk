import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var listening = false
    @State private var keyCapture = KeyCapture()
    @State private var listeningSmartKey = false
    @State private var smartKeyCapture = KeyCapture()
    @State private var keyConflict: String?
    @State private var conflictTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                hotkeysSection

                SettingsSection("Startup") {
                    SettingRow("Launch at login") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                    }
                }

                PrivacySettingsSection()
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
        .onDisappear {
            keyCapture.stop()
            smartKeyCapture.stop()
            conflictTask?.cancel()
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.primary)
            Text("Hotkeys, startup and privacy")
                .font(.caption)
                .foregroundStyle(AppTheme.tertiary)
        }
        .padding(.bottom, 20)
    }

    private var hotkeysSection: some View {
        SettingsSection("Hotkeys") {
            SettingRow("Dictation key") {
                HStack(spacing: 8) {
                    Button("Reset") { applyKey(UInt16(kVK_RightCommand)) }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondary)
                    Button(listening ? "Press a key..." : keyName(settings.hotkeyCode)) { startListening() }
                        .buttonStyle(.bordered)
                        .foregroundStyle(listening ? .orange : AppTheme.primary)
                }
            }
            Divider().background(AppTheme.divider)
            SettingRow("Smart key") {
                HStack(spacing: 8) {
                    Button("Reset") { applySmartKey(UInt16(kVK_Option)) }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondary)
                    Button(listeningSmartKey ? "Press a key..." : keyName(settings.smartHotkeyCode)) {
                        startListeningSmartKey()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(listeningSmartKey ? .orange : AppTheme.primary)
                }
            }
            Text(keyMessage ?? "Hold the dictation key to type what you say. The Smart key works while Smart Mode is on in Models.")
                .font(.system(size: 11))
                .foregroundStyle(keyMessage == nil ? AppTheme.tertiary : AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // A pair saved before the guard existed can still be equal; say so rather than leave the Smart key dead.
    private var keyMessage: String? {
        keyConflict ?? (settings.hotkeyCode == settings.smartHotkeyCode ? "Both keys are the same, so the Smart key does nothing. Change one." : nil)
    }

    private func startListening() {
        listening = true
        keyCapture.start { code in
            applyKey(code)
            listening = false
        }
    }

    private func startListeningSmartKey() {
        listeningSmartKey = true
        smartKeyCapture.start { code in
            applySmartKey(code)
            listeningSmartKey = false
        }
    }

    // One physical key cannot drive both hotkeys: the tap matches the dictation key first, so the
    // Smart key would silently never fire.
    private func applyKey(_ code: UInt16) {
        guard code != settings.smartHotkeyCode else { return refuse("Already used by the Smart key") }
        settings.hotkeyCode = code
        AppController.shared.setupHotkey()
    }

    private func applySmartKey(_ code: UInt16) {
        guard code != settings.hotkeyCode else { return refuse("Already used by the Dictation key") }
        settings.smartHotkeyCode = code
        AppController.shared.setupHotkey()
    }

    private func refuse(_ message: String) {
        keyConflict = message
        conflictTask?.cancel()
        conflictTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { keyConflict = nil }
        }
    }

    private func keyName(_ code: UInt16) -> String { AppTheme.keyLabel(for: code) }
}
