import Foundation
import ServiceManagement

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var selectedTier: UInt8 {
        didSet { UserDefaults.standard.set(Int(selectedTier), forKey: "selectedTier") }
    }

    @Published var selectedLanguage: String? {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage") }
    }

    @Published var hotkeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin(launchAtLogin) }
    }

    private init() {
        let rawTier = UserDefaults.standard.integer(forKey: "selectedTier")
        selectedTier = rawTier > 0 ? UInt8(rawTier) : 1

        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage")

        let rawCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        hotkeyCode = rawCode > 0 ? UInt16(rawCode) : UInt16(0x36) // kVK_RightCommand

        launchAtLogin = (try? SMAppService.mainApp.status) == .enabled
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — not critical
        }
    }
}
