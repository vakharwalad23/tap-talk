import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var listening = false
    @State private var keyCapture = KeyCapture()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader

                SettingsSection("Startup") {
                    SettingRow("Launch at login") {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                    }
                }

                SettingsSection("Hotkey") {
                    SettingRow("Push-to-talk key") {
                        Button(listening ? "Press a key..." : keyName(settings.hotkeyCode)) {
                            startListening()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(listening ? .orange : AppTheme.primary)
                    }
                    Divider().background(AppTheme.divider)
                    Button("Reset to Right Cmd") { applyKey(UInt16(kVK_RightCommand)) }
                        .foregroundStyle(AppTheme.secondary)
                        .font(.callout)
                }
            }
            .padding(24)
        }
        .background(AppTheme.windowBg)
        .onDisappear { keyCapture.stop() }
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

    private func startListening() {
        listening = true
        keyCapture.start { code in
            applyKey(code)
            listening = false
        }
    }

    private func applyKey(_ code: UInt16) {
        settings.hotkeyCode = code
        AppController.shared.setupHotkey()
    }

    private func keyName(_ code: UInt16) -> String { AppTheme.keyLabel(for: code) }
}
